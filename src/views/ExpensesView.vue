<script setup>
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Pencil,
  ReceiptText,
  Search,
  Trash2,
  UsersRound,
  X,
} from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { supabase } from "../lib/supabase";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";

const ledgerStore = useLedgerStore();
const expenseStore = useExpenseStore();
const authStore = useAuthStore();
const members = ref([]);
const membersError = ref("");
const settledExpenseIds = ref(new Set());
const settlementLookupError = ref("");
const editingExpenseId = ref("");
const editError = ref("");
const editSuccess = ref("");
const isSavingEdit = ref(false);
const deletingExpenseId = ref("");
const searchQuery = ref("");
const searchResults = ref(null);
const expenseSearchLoading = ref(false);
const expenseSearchError = ref("");
const editForm = ref({
  title: "",
  amount: "",
  payerUserId: "",
  splitUserIds: [],
  category: "其他",
  expenseDate: "",
  notes: "",
});
let requestId = 0;
let expenseSearchRequestId = 0;

const expenses = computed(() => expenseStore.recentExpenses);
const displayedExpenses = computed(() =>
  searchQuery.value.trim() ? searchResults.value || [] : expenses.value,
);
const incompleteCount = computed(
  () => expenses.value.filter((expense) => !expense.splits?.length).length,
);
const currency = computed(() => {
  try {
    return new Intl.NumberFormat("zh-TW", {
      style: "currency",
      currency: ledgerStore.activeLedger?.currency || "TWD",
      maximumFractionDigits: 2,
    });
  } catch {
    return new Intl.NumberFormat("zh-TW", {
      style: "currency",
      currency: "TWD",
      maximumFractionDigits: 2,
    });
  }
});
const memberMap = computed(
  () => new Map(members.value.map((member) => [member.user_id, member])),
);
const memberName = (userId) => {
  const member = memberMap.value.get(userId);
  return member?.display_name || member?.email?.split("@")[0] || "帳本成員";
};
const formatDate = (value) =>
  new Date(value).toLocaleDateString("zh-TW", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
  });
const canSaveEdit = computed(
  () =>
    editForm.value.title.trim().length > 0 &&
    Number(editForm.value.amount) > 0 &&
    Boolean(editForm.value.payerUserId) &&
    editForm.value.splitUserIds.length > 0,
);
const editPerPerson = computed(() =>
  editForm.value.splitUserIds.length
    ? Number(editForm.value.amount || 0) / editForm.value.splitUserIds.length
    : 0,
);
const isExpenseCreator = (expense) =>
  Boolean(authStore.user?.id && expense.createdBy === authStore.user.id);
const isSettledExpense = (expense) => settledExpenseIds.value.has(expense.id);
const getErrorMessage = (error) => {
  const message = [error?.message, error?.details, error?.hint]
    .filter(Boolean)
    .join(" ");
  if (/update_ledger_expense|PGRST202/i.test(message)) {
    return "資料庫尚未建立費用編輯功能，請先執行 supabase/expense_edit_migration.sql。";
  }
  if (
    /已進入結算|settlement_expenses|prevent_settled_expense_mutation/i.test(
      message,
    )
  ) {
    return "此費用已封存於結算歷史，為保留帳目不能直接編輯；請新增一筆調整費用。";
  }
  if (/PAYER_UPDATE_MISMATCH/i.test(message)) {
    return "資料庫已確認付款人欄位被改回其他值。請檢查 public.expenses 的 UPDATE trigger 或 Supabase 上的 RPC 版本。";
  }
  return message || "發生未知錯誤，請稍後再試。";
};

function beginEdit(expense) {
  editError.value = "";
  editSuccess.value = "";
  if (isSettledExpense(expense)) {
    editError.value =
      "此費用已封存於結算歷史，為保留帳目不能直接編輯；請新增一筆調整費用。";
    return;
  }
  editingExpenseId.value = expense.id;
  editForm.value = {
    title: expense.title,
    amount: String(expense.amount),
    payerUserId: expense.payerUserId || "",
    splitUserIds: (expense.splits || []).map((split) => split.userId),
    category: expense.category || "其他",
    expenseDate: expense.expenseDate || expense.createdAt.slice(0, 10),
    notes: expense.notes || "",
  };
}

function cancelEdit() {
  editingExpenseId.value = "";
  editError.value = "";
}

async function saveEdit() {
  if (!canSaveEdit.value || !editingExpenseId.value) return;
  isSavingEdit.value = true;
  editError.value = "";
  editSuccess.value = "";
  try {
    const updatedExpense = await expenseStore.updateExpense(
      editingExpenseId.value,
      {
        ...editForm.value,
        amount: Number(editForm.value.amount),
      },
    );
    editSuccess.value = `「${updatedExpense.title}」已更新。`;
    editingExpenseId.value = "";
    refreshExpenseSearch();
  } catch (error) {
    editError.value = getErrorMessage(error);
  } finally {
    isSavingEdit.value = false;
  }
}

async function deleteExpense(expense) {
  if (!isExpenseCreator(expense) || deletingExpenseId.value) return;
  const confirmMessage = `確定刪除「${expense.title}」${currency.value.format(expense.amount)}？此操作無法復原。`;
  if (!window.confirm(confirmMessage)) return;

  deletingExpenseId.value = expense.id;
  editError.value = "";
  try {
    await expenseStore.deleteExpense(expense.id);
    if (editingExpenseId.value === expense.id) editingExpenseId.value = "";
    refreshExpenseSearch();
  } catch (error) {
    editError.value = getErrorMessage(error);
  } finally {
    deletingExpenseId.value = "";
  }
}

function refreshExpenseSearch() {
  const query = searchQuery.value.trim();
  if (!query) return;
  const currentRequest = ++expenseSearchRequestId;
  expenseSearchLoading.value = true;
  expenseSearchError.value = "";
  expenseStore
    .searchExpensesByTitle(query)
    .then((results) => {
      if (currentRequest === expenseSearchRequestId)
        searchResults.value = results;
    })
    .catch((error) => {
      if (currentRequest === expenseSearchRequestId)
        expenseSearchError.value =
          error.message || "搜尋支出失敗，請稍後再試。";
    })
    .finally(() => {
      if (currentRequest === expenseSearchRequestId)
        expenseSearchLoading.value = false;
    });
}

async function loadExpensesAndMembers() {
  const ledgerId = ledgerStore.activeLedgerId;
  const currentRequest = ++requestId;
  members.value = [];
  settledExpenseIds.value = new Set();
  membersError.value = "";
  settlementLookupError.value = "";
  if (!ledgerId) return;

  if (
    expenseStore.ledgerId !== ledgerId ||
    expenseStore.loadedLedgerId !== ledgerId
  ) {
    await expenseStore.setLedger(ledgerId);
  }
  if (!supabase) return;

  const [memberResult, settlementResult] = await Promise.all([
    supabase.rpc("list_ledger_members", { p_ledger_id: ledgerId }),
    supabase.from("settlements").select("id").eq("ledger_id", ledgerId),
  ]);
  if (memberResult.error) {
    if (currentRequest === requestId)
      membersError.value = memberResult.error.message;
  } else if (currentRequest === requestId) {
    members.value = memberResult.data || [];
  }

  if (settlementResult.error) {
    if (currentRequest === requestId)
      settlementLookupError.value = settlementResult.error.message;
    return;
  }

  const settlementIds = (settlementResult.data || []).map(
    (settlement) => settlement.id,
  );
  if (!settlementIds.length) return;

  const { data: settledRows, error: settledError } = await supabase
    .from("settlement_expenses")
    .select("expense_id")
    .in("settlement_id", settlementIds);
  if (settledError) {
    if (currentRequest === requestId)
      settlementLookupError.value = settledError.message;
    return;
  }
  if (currentRequest === requestId) {
    settledExpenseIds.value = new Set(
      (settledRows || []).map((row) => row.expense_id),
    );
  }
}

watch(searchQuery, (query, _previousQuery, onCleanup) => {
  const normalizedQuery = query.trim();
  const currentRequest = ++expenseSearchRequestId;
  expenseSearchError.value = "";
  if (!normalizedQuery) {
    searchResults.value = null;
    expenseSearchLoading.value = false;
    return;
  }

  searchResults.value = [];
  expenseSearchLoading.value = true;
  const timer = setTimeout(async () => {
    try {
      const results = await expenseStore.searchExpensesByTitle(normalizedQuery);
      if (currentRequest === expenseSearchRequestId)
        searchResults.value = results;
    } catch (error) {
      if (currentRequest === expenseSearchRequestId)
        expenseSearchError.value =
          error.message || "搜尋支出失敗，請稍後再試。";
    } finally {
      if (currentRequest === expenseSearchRequestId)
        expenseSearchLoading.value = false;
    }
  }, 250);
  onCleanup(() => clearTimeout(timer));
});
watch(
  () => ledgerStore.activeLedgerId,
  () => {
    searchQuery.value = "";
    searchResults.value = null;
    expenseSearchError.value = "";
    expenseSearchRequestId += 1;
    loadExpensesAndMembers();
  },
);
watch(
  [
    () => authStore.user?.user_metadata?.display_name,
    () => authStore.user?.user_metadata?.avatar_emoji,
  ],
  loadExpensesAndMembers,
);
onMounted(loadExpensesAndMembers);
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "歡迎使用分分" }}
    </p>
    <h1>費用紀錄</h1>
  </section>

  <div v-if="ledgerStore.activeLedger" class="notice">
    <ReceiptText :size="17" />{{ ledgerStore.activeLedger.name }}
    的所有支出與分攤明細。
  </div>
  <div v-else class="empty-state">
    <p>請先建立或選擇帳本，再瀏覽費用紀錄。</p>
    <RouterLink class="section-link" to="/ledgers">前往帳本管理</RouterLink>
  </div>

  <template v-if="ledgerStore.activeLedger">
    <p v-if="expenseStore.error" class="expense-error" role="alert">
      {{ expenseStore.error }}
    </p>
    <p v-if="membersError" class="expense-error" role="alert">
      無法載入成員名稱：{{ membersError }}
    </p>
    <p v-if="settlementLookupError" class="expense-error" role="alert">
      無法確認費用是否已結算：{{ settlementLookupError }}
    </p>
    <p v-if="editError && !editingExpenseId" class="expense-error" role="alert">
      {{ editError }}
    </p>
    <p v-if="editSuccess" class="ledger-feedback" role="status">
      {{ editSuccess }}
    </p>
    <div v-if="incompleteCount" class="notice incomplete-notice">
      {{ incompleteCount }} 筆舊費用沒有分攤明細，請在紀錄中展開確認。
    </div>

    <div class="section-row expense-page-heading">
      <h2>全部支出</h2>
      <span class="settlement-count">{{ displayedExpenses.length }} 筆</span>
    </div>

    <label class="expense-search" for="expense-search-input">
      <Search :size="17" aria-hidden="true" />
      <input
        id="expense-search-input"
        v-model="searchQuery"
        autocomplete="off"
        placeholder="搜尋支出名稱"
        type="text"
      />
      <button
        v-if="searchQuery"
        type="button"
        aria-label="清除搜尋"
        @click="searchQuery = ''"
      >
        <X :size="16" />
      </button>
    </label>
    <p class="expense-search-hint">輸入關鍵字搜尋此帳本的全部支出名稱</p>
    <p v-if="expenseSearchError" class="expense-error" role="alert">
      {{ expenseSearchError }}
    </p>

    <div v-if="expenseStore.isLoading" class="member-state" role="status">
      正在載入費用紀錄…
    </div>
    <div v-else-if="expenseSearchLoading" class="member-state" role="status">
      正在搜尋支出…
    </div>
    <div
      v-else-if="!displayedExpenses.length && !searchQuery.trim()"
      class="empty-state settlement-empty"
    >
      <ReceiptText :size="25" />
      <p>這本帳本還沒有費用紀錄。</p>
      <RouterLink class="section-link" to="/expenses/new">新增費用</RouterLink>
    </div>
    <div
      v-else-if="!displayedExpenses.length"
      class="empty-state settlement-empty"
    >
      <Search :size="25" />
      <p>找不到符合「{{ searchQuery.trim() }}」的支出。</p>
    </div>
    <div v-else class="settlement-expense-list">
      <details
        v-for="expense in displayedExpenses"
        :key="expense.id"
        class="settlement-expense"
      >
        <summary>
          <span class="expense-symbol"><ReceiptText :size="18" /></span>
          <span class="expense-info">
            <strong>{{ expense.title }}</strong>
            <span
              >{{ memberName(expense.payerUserId) }} 付款・{{
                expense.category
              }}・{{
                formatDate(expense.expenseDate || expense.createdAt)
              }}</span
            >
          </span>
          <span class="expense-amount">{{
            currency.format(expense.amount)
          }}</span>
        </summary>
        <div v-if="editingExpenseId !== expense.id" class="expense-detail">
          <div class="expense-detail-meta">
            <span>付款人</span
            ><strong>{{ memberName(expense.payerUserId) }}</strong>
          </div>
          <div class="expense-detail-meta">
            <span>總金額</span
            ><strong>{{ currency.format(expense.amount) }}</strong>
          </div>
          <div v-if="expense.notes" class="expense-detail-meta">
            <span>備註</span><strong>{{ expense.notes }}</strong>
          </div>
          <div class="expense-split-heading">分攤明細</div>
          <template v-if="expense.splits?.length">
            <div
              v-for="split in expense.splits"
              :key="split.userId"
              class="expense-detail-meta split-detail-row"
            >
              <span>{{ memberName(split.userId) }}</span
              ><strong>{{ currency.format(split.amount) }}</strong>
            </div>
          </template>
          <p v-else class="legacy-split-note">
            此筆費用尚未設定分攤成員，因此未納入結算計算。
          </p>
          <div
            v-if="isExpenseCreator(expense)"
            class="expense-management-actions"
          >
            <button
              class="expense-edit-button"
              :disabled="isSettledExpense(expense)"
              :title="
                isSettledExpense(expense)
                  ? '已結算費用不可直接編輯'
                  : '編輯費用'
              "
              type="button"
              @click.prevent="beginEdit(expense)"
            >
              <Pencil :size="15" />{{
                isSettledExpense(expense) ? "已結算" : "編輯"
              }}
            </button>
            <button
              class="expense-delete-button"
              :disabled="
                deletingExpenseId === expense.id || isSettledExpense(expense)
              "
              :title="
                isSettledExpense(expense) ? '已結算費用不可刪除' : '刪除費用'
              "
              type="button"
              @click.prevent="deleteExpense(expense)"
            >
              <Trash2 :size="15" />{{
                deletingExpenseId === expense.id
                  ? "刪除中…"
                  : isSettledExpense(expense)
                    ? "已封存"
                    : "刪除"
              }}
            </button>
          </div>
        </div>
        <form v-else class="expense-edit-form" @submit.prevent="saveEdit">
          <div class="expense-edit-title-row">
            <strong>編輯費用</strong>
            <button
              class="expense-edit-close"
              type="button"
              aria-label="取消編輯"
              @click="cancelEdit"
            >
              <X :size="17" />
            </button>
          </div>
          <div class="field">
            <label :for="`edit-title-${expense.id}`">費用名稱</label>
            <input
              :id="`edit-title-${expense.id}`"
              v-model="editForm.title"
              maxlength="120"
              required
            />
          </div>
          <div class="field">
            <label :for="`edit-amount-${expense.id}`"
              >金額（{{ ledgerStore.activeLedger?.currency || "TWD" }}）</label
            >
            <input
              :id="`edit-amount-${expense.id}`"
              v-model="editForm.amount"
              class="amount-input"
              inputmode="decimal"
              min="0.01"
              max="9999999999.99"
              required
              step="0.01"
              type="number"
            />
          </div>
          <div class="field">
            <label :for="`edit-date-${expense.id}`">日期</label>
            <input
              :id="`edit-date-${expense.id}`"
              v-model="editForm.expenseDate"
              required
              type="date"
            />
          </div>
          <div class="field">
            <label :for="`edit-category-${expense.id}`">分類</label>
            <select
              :id="`edit-category-${expense.id}`"
              v-model="editForm.category"
            >
              <option>餐飲</option>
              <option>交通</option>
              <option>住宿</option>
              <option>購物</option>
              <option>其他</option>
            </select>
          </div>
          <div class="field">
            <label :for="`edit-payer-${expense.id}`">付款人</label>
            <select
              :id="`edit-payer-${expense.id}`"
              v-model="editForm.payerUserId"
              required
            >
              <option
                v-for="member in members"
                :key="member.user_id"
                :value="member.user_id"
              >
                {{ member.display_name || member.email.split("@")[0] }}
              </option>
            </select>
          </div>
          <fieldset class="split-fieldset expense-edit-splits">
            <legend><UsersRound :size="15" />分攤成員</legend>
            <label
              v-for="member in members"
              :key="member.user_id"
              class="split-member"
            >
              <input
                v-model="editForm.splitUserIds"
                type="checkbox"
                :value="member.user_id"
              />
              <span class="split-check"><Check :size="14" /></span>
              <span class="split-member-name"
                ><strong>{{
                  member.display_name || member.email.split("@")[0]
                }}</strong
                ><small>{{ member.email }}</small></span
              >
              <span
                v-if="editForm.splitUserIds.includes(member.user_id)"
                class="split-preview"
                >{{ currency.format(editPerPerson) }}</span
              >
            </label>
            <p v-if="!editForm.splitUserIds.length" class="split-validation">
              請至少選擇一位分攤成員。
            </p>
          </fieldset>
          <div class="field">
            <label :for="`edit-notes-${expense.id}`">備註</label>
            <textarea
              :id="`edit-notes-${expense.id}`"
              v-model="editForm.notes"
              maxlength="500"
              placeholder="選填"
              rows="3"
            />
          </div>
          <p v-if="editError" class="expense-error" role="alert">
            {{ editError }}
          </p>
          <div class="expense-edit-buttons">
            <button
              class="expense-edit-button"
              type="button"
              :disabled="isSavingEdit"
              @click="cancelEdit"
            >
              取消
            </button>
            <button
              class="primary-button"
              type="submit"
              :disabled="!canSaveEdit || isSavingEdit"
            >
              <Check :size="16" />{{ isSavingEdit ? "儲存中…" : "儲存變更" }}
            </button>
          </div>
        </form>
      </details>
    </div>
  </template>
</template>
