import { defineStore } from "pinia";
import { computed, ref } from "vue";
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

export const useExpenseStore = defineStore("expenses", () => {
  const expenses = ref([]);
  const ledgerId = ref("");
  const loadedLedgerId = ref("");
  const isLoading = ref(false);
  const error = ref("");
  const totalAmount = computed(() =>
    expenses.value.reduce((total, expense) => total + expense.amount, 0),
  );
  const recentExpenses = computed(() =>
    [...expenses.value].sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
  );

  function persistCache() {
    if (!ledgerId.value) return;
    localStorage.setItem(
      storageKey(ledgerId.value),
      JSON.stringify(expenses.value),
    );
  }

  async function setLedger(nextLedgerId) {
    if (
      nextLedgerId === ledgerId.value &&
      loadedLedgerId.value === nextLedgerId
    )
      return;
    ledgerId.value = nextLedgerId;
    loadedLedgerId.value = "";
    error.value = "";
    if (!nextLedgerId) {
      expenses.value = [];
      isLoading.value = false;
      return;
    }

    expenses.value = loadCachedExpenses(nextLedgerId);
    if (!supabase) {
      error.value = "未連線 Supabase；目前顯示本機快取資料。";
      return;
    }

    isLoading.value = true;
    const targetLedgerId = nextLedgerId;
    try {
      await migrateLegacyExpenses(targetLedgerId);
      const { data, error } = await supabase
        .from("expenses")
        .select(
          "id, ledger_id, title, amount, paid_by, payer_name, created_by, category, expense_date, notes, created_at, expense_splits(user_id, amount)",
        )
        .eq("ledger_id", targetLedgerId)
        .order("expense_date", { ascending: false })
        .order("created_at", { ascending: false });
      if (error) throw error;
      if (ledgerId.value !== targetLedgerId) return;

      expenses.value = (data || []).map((row) => ({
        id: row.id,
        ledgerId: row.ledger_id,
        title: row.title,
        amount: Number(row.amount),
        payerUserId: row.paid_by,
        payer: row.payer_name || "帳本成員",
        createdBy: row.created_by,
        category: row.category,
        createdAt: row.created_at,
        expenseDate: row.expense_date,
        notes: row.notes || "",
        splits: (row.expense_splits || []).map((split) => ({
          userId: split.user_id,
          amount: Number(split.amount),
        })),
      }));
      persistCache();
      loadedLedgerId.value = targetLedgerId;
    } catch (err) {
      if (ledgerId.value === targetLedgerId) {
        error.value = `無法從資料庫載入支出：${err.message}`;
      }
    } finally {
      if (ledgerId.value === targetLedgerId) isLoading.value = false;
    }
  }

  async function migrateLegacyExpenses(targetLedgerId) {
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
      localStorage.setItem(migrationKey(targetLedgerId), "true");
      return;
    }

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();
    if (userError) throw userError;
    if (!user) throw new Error("請重新登入後再同步本機支出。");
    if (ledgerId.value !== targetLedgerId) return;

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
  }

  async function addExpense(expense) {
    if (!ledgerId.value) throw new Error("請先建立或選擇帳本。");
    if (!supabase) throw new Error("Supabase 未設定，支出無法寫入資料庫。");
    const splitUserIds = [...new Set(expense.splitUserIds || [])];
    if (!expense.payerUserId) throw new Error("請選擇付款人。");
    if (!splitUserIds.length) throw new Error("請至少選擇一位分攤成員。");

    const authStore = useAuthStore();
    const user = authStore.user;
    if (!user) throw new Error("登入狀態已失效，請重新登入後再試。");

    const now = new Date();
    const targetLedgerId = ledgerId.value;
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
        "id, ledger_id, title, amount, paid_by, payer_name, created_by, category, expense_date, notes, created_at, expense_splits(user_id, amount)",
      )
      .eq("id", expenseId)
      .single();
    if (error) throw error;
    if (ledgerId.value !== targetLedgerId) {
      throw new Error("支出已儲存，但目前已切換帳本。請返回該帳本查看。");
    }

    const savedExpense = {
      id: data.id,
      ledgerId: data.ledger_id,
      title: data.title,
      amount: Number(data.amount),
      payer: data.payer_name || "帳本成員",
      payerUserId: data.paid_by,
      createdBy: data.created_by,
      category: data.category,
      createdAt: data.created_at,
      expenseDate: data.expense_date,
      notes: data.notes || "",
      splits: (data.expense_splits || []).map((split) => ({
        userId: split.user_id,
        amount: Number(split.amount),
      })),
    };
    expenses.value.unshift(savedExpense);
    persistCache();
    return savedExpense;
  }

  async function updateExpense(expenseId, expense) {
    if (!ledgerId.value) throw new Error("請先選擇帳本。");
    if (!supabase) throw new Error("Supabase 未設定，費用無法更新。");
    const authStore = useAuthStore();
    if (!authStore.user) throw new Error("登入狀態已失效，請重新登入後再試。");

    const targetLedgerId = ledgerId.value;
    const splitUserIds = [...new Set(expense.splitUserIds || [])];
    const { data: updatedId, error: updateError } = await supabase.rpc(
      "update_ledger_expense",
      {
        p_expense_id: expenseId,
        p_title: expense.title.trim(),
        p_amount: Number(expense.amount),
        p_paid_by: expense.payerUserId,
        p_category: expense.category || "其他",
        p_expense_date: expense.expenseDate,
        p_notes: expense.notes || "",
        p_split_user_ids: splitUserIds,
      },
    );
    if (updateError) throw updateError;
    if (updatedId !== expenseId)
      throw new Error("資料庫回傳的費用識別碼不符。");

    const { data, error } = await supabase
      .from("expenses")
      .select(
        "id, ledger_id, title, amount, paid_by, payer_name, created_by, category, expense_date, notes, created_at, expense_splits(user_id, amount)",
      )
      .eq("id", expenseId)
      .single();
    if (error) throw error;
    if (ledgerId.value !== targetLedgerId) {
      throw new Error("費用已更新，但目前已切換帳本。請返回原帳本查看。");
    }

    const updatedExpense = {
      id: data.id,
      ledgerId: data.ledger_id,
      title: data.title,
      amount: Number(data.amount),
      payer: data.payer_name || "帳本成員",
      payerUserId: data.paid_by,
      createdBy: data.created_by,
      category: data.category,
      createdAt: data.created_at,
      expenseDate: data.expense_date,
      notes: data.notes || "",
      splits: (data.expense_splits || []).map((split) => ({
        userId: split.user_id,
        amount: Number(split.amount),
      })),
    };
    const expenseIndex = expenses.value.findIndex(
      (item) => item.id === expenseId,
    );
    if (expenseIndex !== -1)
      expenses.value.splice(expenseIndex, 1, updatedExpense);
    persistCache();
    return updatedExpense;
  }

  async function deleteExpense(expenseId) {
    if (!supabase) throw new Error("Supabase 未設定，無法刪除支出。");
    const { error } = await supabase
      .from("expenses")
      .delete()
      .eq("id", expenseId);
    if (error) throw error;
    expenses.value = expenses.value.filter(
      (expense) => expense.id !== expenseId,
    );
    persistCache();
  }

  return {
    expenses,
    ledgerId,
    loadedLedgerId,
    isLoading,
    error,
    totalAmount,
    recentExpenses,
    persistCache,
    setLedger,
    migrateLegacyExpenses,
    addExpense,
    updateExpense,
    deleteExpense,
  };
});
