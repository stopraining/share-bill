<script setup>
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Pencil,
  ReceiptText,
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
const editingExpenseId = ref("");
const editError = ref("");
const isSavingEdit = ref(false);
const deletingExpenseId = ref("");
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

const expenses = computed(() => expenseStore.recentExpenses);
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
const getErrorMessage = (error) => {
  const message = error?.message || "發生未知錯誤。";
  if (message.includes("update_ledger_expense")) {
    return "資料庫尚未建立費用編輯功能，請先執行 supabase/expense_edit_migration.sql。";
  }
  return message;
};

function beginEdit(expense) {
  editError.value = "";
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
  try {
    await expenseStore.updateExpense(editingExpenseId.value, {
      ...editForm.value,
      amount: Number(editForm.value.amount),
    });
    editingExpenseId.value = "";
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
  } catch (error) {
    editError.value = getErrorMessage(error);
  } finally {
    deletingExpenseId.value = "";
  }
}

async function loadExpensesAndMembers() {
  const ledgerId = ledgerStore.activeLedgerId;
  const currentRequest = ++requestId;
  members.value = [];
  membersError.value = "";
  if (!ledgerId) return;

  if (
    expenseStore.ledgerId !== ledgerId ||
    expenseStore.loadedLedgerId !== ledgerId
  ) {
    await expenseStore.setLedger(ledgerId);
  }
  if (!supabase) return;

  const { data, error } = await supabase.rpc("list_ledger_members", {
    p_ledger_id: ledgerId,
  });
  if (error) {
    if (currentRequest === requestId) membersError.value = error.message;
    return;
  }
  if (currentRequest === requestId) members.value = data || [];
}

watch(() => ledgerStore.activeLedgerId, loadExpensesAndMembers);
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
    <p v-if="editError && !editingExpenseId" class="expense-error" role="alert">
      {{ editError }}
    </p>
    <div v-if="incompleteCount" class="notice incomplete-notice">
      {{ incompleteCount }} 筆舊費用沒有分攤明細，請在紀錄中展開確認。
    </div>

    <div class="section-row expense-page-heading">
      <h2>全部支出</h2>
      <span class="settlement-count">{{ expenses.length }} 筆</span>
    </div>

    <div v-if="expenseStore.isLoading" class="member-state" role="status">
      正在載入費用紀錄…
    </div>
    <div v-else-if="!expenses.length" class="empty-state settlement-empty">
      <ReceiptText :size="25" />
      <p>這本帳本還沒有費用紀錄。</p>
      <RouterLink class="section-link" to="/expenses/new">新增費用</RouterLink>
    </div>
    <div v-else class="settlement-expense-list">
      <details
        v-for="expense in expenses"
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
              type="button"
              @click.prevent="beginEdit(expense)"
            >
              <Pencil :size="15" />編輯
            </button>
            <button
              class="expense-delete-button"
              :disabled="deletingExpenseId === expense.id"
              type="button"
              @click.prevent="deleteExpense(expense)"
            >
              <Trash2 :size="15" />{{
                deletingExpenseId === expense.id ? "刪除中…" : "刪除"
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

    <RouterLink class="primary-button expense-add-button" to="/expenses/new">
      <ArrowLeft :size="17" />新增一筆費用
    </RouterLink>
  </template>
</template>
