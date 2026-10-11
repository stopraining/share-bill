import { defineStore } from "pinia";
import { supabase } from "../lib/supabase";
import { useAuthStore } from "./auth";

const LEGACY_STORAGE_KEY = "share-bill-expenses";
const storageKey = (ledgerId) => `share-bill-expenses:${ledgerId}`;
const migrationKey = (ledgerId) => `share-bill-expenses-migrated:${ledgerId}`;

function loadCachedExpenses(ledgerId) {
  if (!ledgerId) return [];
  try {
    const saved = localStorage.getItem(storageKey(ledgerId));
    if (saved) return JSON.parse(saved);
  } catch {
    return [];
  }
  return [];
}

export const useExpenseStore = defineStore("expenses", {
  state: () => ({
    expenses: [],
    ledgerId: "",
    loadedLedgerId: "",
    isLoading: false,
    error: "",
  }),
  getters: {
    totalAmount: (state) =>
      state.expenses.reduce((total, expense) => total + expense.amount, 0),
    recentExpenses: (state) =>
      [...state.expenses].sort((a, b) =>
        b.createdAt.localeCompare(a.createdAt),
      ),
  },
  actions: {
    persistCache() {
      if (!this.ledgerId) return;
      localStorage.setItem(
        storageKey(this.ledgerId),
        JSON.stringify(this.expenses),
      );
    },
    async setLedger(ledgerId) {
      if (ledgerId === this.ledgerId && this.loadedLedgerId === ledgerId)
        return;
      this.ledgerId = ledgerId;
      this.loadedLedgerId = "";
      this.error = "";
      if (!ledgerId) {
        this.expenses = [];
        this.isLoading = false;
        return;
      }

      this.expenses = loadCachedExpenses(ledgerId);
      if (!supabase) {
        this.error = "未連線 Supabase；目前顯示本機快取資料。";
        return;
      }

      this.isLoading = true;
      const targetLedgerId = ledgerId;
      try {
        await this.migrateLegacyExpenses(targetLedgerId);
        const { data, error } = await supabase
          .from("expenses")
          .select(
            "id, ledger_id, title, amount, paid_by, payer_name, category, expense_date, created_at, expense_splits(user_id, amount)",
          )
          .eq("ledger_id", targetLedgerId)
          .order("expense_date", { ascending: false })
          .order("created_at", { ascending: false });
        if (error) throw error;
        if (this.ledgerId !== targetLedgerId) return;

        this.expenses = (data || []).map((row) => ({
          id: row.id,
          ledgerId: row.ledger_id,
          title: row.title,
          amount: Number(row.amount),
          payerUserId: row.paid_by,
          payer: row.payer_name || "帳本成員",
          category: row.category,
          createdAt: row.created_at,
          expenseDate: row.expense_date,
          splits: (row.expense_splits || []).map((split) => ({
            userId: split.user_id,
            amount: Number(split.amount),
          })),
        }));
        this.persistCache();
        this.loadedLedgerId = targetLedgerId;
      } catch (error) {
        if (this.ledgerId === targetLedgerId) {
          this.error = `無法從資料庫載入支出：${error.message}`;
        }
      } finally {
        if (this.ledgerId === targetLedgerId) this.isLoading = false;
      }
    },
    async migrateLegacyExpenses(targetLedgerId) {
      if (
        !supabase ||
        !targetLedgerId ||
        localStorage.getItem(migrationKey(targetLedgerId))
      )
        return;

      const cached = loadCachedExpenses(targetLedgerId);
      let legacy = [];
      try {
        const rawLegacy = localStorage.getItem(LEGACY_STORAGE_KEY);
        legacy = rawLegacy ? JSON.parse(rawLegacy) : [];
      } catch {
        throw new Error(
          "舊有本機支出資料格式錯誤；為避免遺失，請先備份瀏覽器資料。",
        );
      }
      if (!Array.isArray(legacy)) legacy = [];
      const legacyForThisLedger = legacy.map((expense) => ({
        ...expense,
        ledgerId: targetLedgerId,
      }));
      const pendingExpenses = [...cached, ...legacyForThisLedger];
      if (!pendingExpenses.length) {
        localStorage.setItem(migrationKey(this.ledgerId), "true");
        return;
      }

      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser();
      if (userError) throw userError;
      if (!user) throw new Error("請重新登入後再同步本機支出。");
      if (this.ledgerId !== targetLedgerId) return;

      const rows = pendingExpenses.map((expense) => ({
        id: expense.id,
        ledger_id: targetLedgerId,
        title: expense.title,
        amount: Number(expense.amount),
        currency: "TWD",
        paid_by: user.id,
        created_by: user.id,
        payer_name:
          expense.payer || user.user_metadata?.display_name || user.email,
        category: expense.category || "其他",
        expense_date:
          expense.createdAt?.slice(0, 10) ||
          new Date().toISOString().slice(0, 10),
      }));

      const { error } = await supabase
        .from("expenses")
        .upsert(rows, { onConflict: "id" });
      if (error) throw error;
      localStorage.setItem(migrationKey(targetLedgerId), "true");
      if (legacy.length) localStorage.removeItem(LEGACY_STORAGE_KEY);
    },
    async addExpense(expense) {
      if (!this.ledgerId) throw new Error("請先建立或選擇帳本。");
      if (!supabase) throw new Error("Supabase 未設定，支出無法寫入資料庫。");
      const splitUserIds = [...new Set(expense.splitUserIds || [])];
      if (!expense.payerUserId) throw new Error("請選擇付款人。");
      if (!splitUserIds.length) throw new Error("請至少選擇一位分攤成員。");

      const authStore = useAuthStore();
      const user = authStore.user;
      if (!user) throw new Error("登入狀態已失效，請重新登入後再試。");

      const now = new Date();
      const targetLedgerId = this.ledgerId;
      const { data: expenseId, error: createError } = await supabase.rpc(
        "create_ledger_expense",
        {
          p_ledger_id: targetLedgerId,
          p_title: expense.title.trim(),
          p_amount: Number(expense.amount),
          p_paid_by: expense.payerUserId,
          p_category: expense.category || "其他",
          p_expense_date: expense.expenseDate || now.toISOString().slice(0, 10),
          p_notes: expense.notes || "",
          p_split_user_ids: splitUserIds,
        },
      );
      if (createError) throw createError;

      const { data, error } = await supabase
        .from("expenses")
        .select(
          "id, ledger_id, title, amount, paid_by, payer_name, category, expense_date, created_at, expense_splits(user_id, amount)",
        )
        .eq("id", expenseId)
        .single();
      if (error) throw error;
      if (this.ledgerId !== targetLedgerId) {
        throw new Error("支出已儲存，但目前已切換帳本。請返回該帳本查看。");
      }

      const savedExpense = {
        id: data.id,
        ledgerId: data.ledger_id,
        title: data.title,
        amount: Number(data.amount),
        payer: data.payer_name || "帳本成員",
        payerUserId: data.paid_by,
        category: data.category,
        createdAt: data.created_at,
        expenseDate: data.expense_date,
        splits: (data.expense_splits || []).map((split) => ({
          userId: split.user_id,
          amount: Number(split.amount),
        })),
      };
      this.expenses.unshift(savedExpense);
      this.persistCache();
      return savedExpense;
    },
    async deleteExpense(expenseId) {
      if (!supabase) throw new Error("Supabase 未設定，無法刪除支出。");
      const { error } = await supabase
        .from("expenses")
        .delete()
        .eq("id", expenseId);
      if (error) throw error;
      this.expenses = this.expenses.filter(
        (expense) => expense.id !== expenseId,
      );
      this.persistCache();
    },
  },
});
