<script setup>
import {
  ArrowRight,
  CircleDollarSign,
  HandCoins,
  Info,
  ReceiptText,
  UsersRound,
} from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { supabase } from "../lib/supabase";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";

const ledgerStore = useLedgerStore();
const expenseStore = useExpenseStore();
const members = ref([]);
const membersLoading = ref(false);
const membersError = ref("");
let dataRequestId = 0;

const currencyCode = computed(
  () => ledgerStore.activeLedger?.currency || "TWD",
);
const currency = computed(() => {
  try {
    return new Intl.NumberFormat("zh-TW", {
      style: "currency",
      currency: currencyCode.value,
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
const expenses = computed(() => expenseStore.recentExpenses);
const expensesWithSplits = computed(() =>
  expenses.value.filter((expense) => expense.splits?.length),
);
const incompleteExpenses = computed(() =>
  expenses.value.filter((expense) => !expense.splits?.length),
);
const totalSpend = computed(() =>
  expenses.value.reduce((total, expense) => total + expense.amount, 0),
);

const balances = computed(() => {
  const centsByMember = new Map(
    members.value.map((member) => [member.user_id, 0]),
  );

  for (const expense of expensesWithSplits.value) {
    if (!centsByMember.has(expense.payerUserId)) continue;
    centsByMember.set(
      expense.payerUserId,
      centsByMember.get(expense.payerUserId) + Math.round(expense.amount * 100),
    );
    for (const split of expense.splits) {
      if (!centsByMember.has(split.userId)) continue;
      centsByMember.set(
        split.userId,
        centsByMember.get(split.userId) - Math.round(split.amount * 100),
      );
    }
  }

  return members.value.map((member) => ({
    ...member,
    netCents: centsByMember.get(member.user_id) || 0,
  }));
});

const transfers = computed(() => {
  const debtors = balances.value
    .filter((member) => member.netCents < 0)
    .map((member) => ({ ...member, remaining: -member.netCents }))
    .sort((a, b) => b.remaining - a.remaining);
  const creditors = balances.value
    .filter((member) => member.netCents > 0)
    .map((member) => ({ ...member, remaining: member.netCents }))
    .sort((a, b) => b.remaining - a.remaining);
  const suggested = [];
  let debtorIndex = 0;
  let creditorIndex = 0;

  while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
    const debtor = debtors[debtorIndex];
    const creditor = creditors[creditorIndex];
    const amountCents = Math.min(debtor.remaining, creditor.remaining);
    if (amountCents > 0) {
      suggested.push({
        from: debtor,
        to: creditor,
        amount: amountCents / 100,
      });
    }
    debtor.remaining -= amountCents;
    creditor.remaining -= amountCents;
    if (!debtor.remaining) debtorIndex += 1;
    if (!creditor.remaining) creditorIndex += 1;
  }
  return suggested;
});

async function loadLedgerData() {
  const ledgerId = ledgerStore.activeLedgerId;
  const requestId = ++dataRequestId;
  members.value = [];
  membersError.value = "";

  if (!ledgerId) {
    membersLoading.value = false;
    return;
  }

  membersLoading.value = true;
  try {
    if (
      expenseStore.ledgerId !== ledgerId ||
      expenseStore.loadedLedgerId !== ledgerId
    ) {
      await expenseStore.setLedger(ledgerId);
    }
    if (!supabase) throw new Error("Supabase 尚未設定。");
    const { data, error } = await supabase.rpc("list_ledger_members", {
      p_ledger_id: ledgerId,
    });
    if (error) throw error;
    if (requestId === dataRequestId) members.value = data || [];
  } catch (error) {
    if (requestId === dataRequestId) membersError.value = error.message;
  } finally {
    if (requestId === dataRequestId) membersLoading.value = false;
  }
}

watch(() => ledgerStore.activeLedgerId, loadLedgerData);
onMounted(loadLedgerData);
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "歡迎使用分分" }}
    </p>
    <h1>結算明細</h1>
  </section>

  <div v-if="!ledgerStore.activeLedger" class="empty-state">
    <HandCoins :size="27" />
    <p>請先建立或選擇帳本，再查看結算。</p>
    <RouterLink class="section-link" to="/ledgers">前往帳本管理</RouterLink>
  </div>
  <template v-else>
    <div class="notice">
      <Info
        :size="17"
      />結算依「實際付款人」和「分攤成員」計算；只列出精簡後需要轉帳的款項。
    </div>

    <p v-if="expenseStore.error" class="expense-error" role="alert">
      {{ expenseStore.error }}
    </p>
    <p v-if="membersError" class="expense-error" role="alert">
      無法載入成員資料：{{ membersError }}。請確認
      <strong>list_ledger_members</strong> RPC 已部署。
    </p>
    <div v-if="incompleteExpenses.length" class="notice incomplete-notice">
      <Info :size="17" />有
      {{
        incompleteExpenses.length
      }}
      筆費用沒有分攤明細，無法納入結算；請至「瀏覽所有費用」檢視。
    </div>

    <div class="settlement-summary-grid">
      <article class="settlement-summary-card">
        <span class="settlement-summary-icon"
          ><CircleDollarSign :size="18"
        /></span>
        <small>帳本總支出</small>
        <strong>{{ currency.format(totalSpend) }}</strong>
      </article>
      <article class="settlement-summary-card">
        <span class="settlement-summary-icon"><ReceiptText :size="18" /></span>
        <small>費用項目</small>
        <strong>{{ expenses.length }} 筆</strong>
      </article>
    </div>

    <section>
      <div class="section-row settlement-section-row">
        <h2>誰需要轉帳</h2>
        <span class="settlement-count">{{ transfers.length }} 筆</span>
      </div>
      <p v-if="membersLoading" class="member-state" role="status">
        正在計算結算…
      </p>
      <div
        v-else-if="expenseStore.isLoading"
        class="member-state"
        role="status"
      >
        正在載入費用紀錄…
      </div>
      <div
        v-else-if="!expensesWithSplits.length"
        class="empty-state settlement-empty"
      >
        <HandCoins :size="25" />
        <p>
          {{
            expenses.length
              ? "目前的費用尚未設定分攤對象，無法計算結算。"
              : "目前沒有待結算的款項"
          }}
        </p>
        <RouterLink
          v-if="!expenses.length"
          class="section-link"
          to="/expenses/new"
          >新增第一筆費用</RouterLink
        >
      </div>
      <div v-else-if="!transfers.length" class="settled-banner">
        <span class="settled-check">✓</span>
        <span
          ><strong>帳目已結清</strong><small>目前沒有人需要轉帳。</small></span
        >
      </div>
      <div v-else class="transfer-list">
        <article
          v-for="(transfer, index) in transfers"
          :key="`${transfer.from.user_id}-${transfer.to.user_id}-${index}`"
          class="transfer-card"
        >
          <span class="transfer-person debtor"
            ><span class="transfer-avatar">{{
              memberName(transfer.from.user_id).slice(0, 1).toUpperCase()
            }}</span
            ><strong>{{ memberName(transfer.from.user_id) }}</strong></span
          >
          <span class="transfer-direction"
            ><span>{{ currency.format(transfer.amount) }}</span
            ><ArrowRight :size="17"
          /></span>
          <span class="transfer-person creditor"
            ><span class="transfer-avatar">{{
              memberName(transfer.to.user_id).slice(0, 1).toUpperCase()
            }}</span
            ><strong>{{ memberName(transfer.to.user_id) }}</strong></span
          >
        </article>
      </div>
    </section>

    <section>
      <div class="section-row settlement-section-row">
        <h2>每人收付餘額</h2>
        <UsersRound :size="17" />
      </div>
      <div v-if="balances.length" class="content-card settlement-balances">
        <article
          v-for="member in balances"
          :key="member.user_id"
          class="settlement-balance-row"
        >
          <span class="transfer-avatar">{{
            memberName(member.user_id).slice(0, 1).toUpperCase()
          }}</span>
          <span class="settlement-balance-name"
            ><strong>{{ memberName(member.user_id) }}</strong
            ><small>{{
              member.role === "owner"
                ? "擁有者"
                : member.role === "admin"
                  ? "管理員"
                  : "成員"
            }}</small></span
          >
          <span
            class="net-balance"
            :class="{
              positive: member.netCents > 0,
              negative: member.netCents < 0,
            }"
          >
            {{
              member.netCents > 0
                ? "應收 "
                : member.netCents < 0
                  ? "應付 "
                  : "已平衡 "
            }}{{ currency.format(Math.abs(member.netCents) / 100) }}
          </span>
        </article>
      </div>
      <div v-else-if="!membersLoading && !membersError" class="empty-state">
        尚無帳本成員資料。
      </div>
    </section>

    <RouterLink class="quick-action settlement-expenses-link" to="/expenses">
      <span class="quick-icon"><ReceiptText :size="19" /></span>
      <span
        ><strong>瀏覽所有費用</strong
        ><span>{{ expenses.length }} 筆紀錄與分攤細項</span></span
      >
      <ArrowRight :size="17" />
    </RouterLink>
  </template>
</template>
