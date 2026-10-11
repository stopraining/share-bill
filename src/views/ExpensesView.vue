<script setup>
import { ArrowLeft, ArrowRight, ReceiptText } from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { supabase } from "../lib/supabase";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";

const ledgerStore = useLedgerStore();
const expenseStore = useExpenseStore();
const members = ref([]);
const membersError = ref("");
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
    <ReceiptText :size="17" />{{
      ledgerStore.activeLedger.name
    }}
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
        <div class="expense-detail">
          <div class="expense-detail-meta">
            <span>付款人</span
            ><strong>{{ memberName(expense.payerUserId) }}</strong>
          </div>
          <div class="expense-detail-meta">
            <span>總金額</span
            ><strong>{{ currency.format(expense.amount) }}</strong>
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
        </div>
      </details>
    </div>

    <RouterLink class="primary-button expense-add-button" to="/expenses/new">
      <ArrowLeft :size="17" />新增一筆費用
    </RouterLink>
  </template>
</template>
