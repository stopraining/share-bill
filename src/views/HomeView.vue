<script setup>
import {
  ArrowRight,
  CircleDollarSign,
  HandCoins,
  Layers3,
  Plus,
  ReceiptText,
} from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";
import { supabase } from "../lib/supabase";

const expenseStore = useExpenseStore();
const ledgerStore = useLedgerStore();
const authStore = useAuthStore();
const roundSummary = ref({ amount: 0, count: 0, isActive: false });
const roundLoading = ref(false);
const roundSummaryNote = ref("");
const members = ref([]);
let summaryRequestId = 0;
let memberRequestId = 0;

const currency = computed(
  () =>
    new Intl.NumberFormat("zh-TW", {
      style: "currency",
      currency: ledgerStore.activeLedger?.currency || "TWD",
      maximumFractionDigits: 2,
    }),
);
const formattedTotal = computed(() =>
  currency.value.format(roundSummary.value.amount),
);
const roundLabel = computed(() =>
  roundSummary.value.isActive ? "本輪結算金額" : "待結算分帳金額",
);
const expenseCountLabel = computed(() =>
  roundSummary.value.isActive ? "本輪已封存" : "等待開始結算",
);
const memberMap = computed(
  () => new Map(members.value.map((member) => [member.user_id, member])),
);

function payerName(expense) {
  const member = memberMap.value.get(expense.payerUserId);
  return (
    member?.display_name ||
    member?.email?.split("@")[0] ||
    expense.payer ||
    "帳本成員"
  );
}

async function loadMembers(ledgerId) {
  const requestId = ++memberRequestId;
  members.value = [];
  if (!ledgerId || !supabase) return;

  const { data, error } = await supabase.rpc("list_ledger_members", {
    p_ledger_id: ledgerId,
  });
  if (!error && requestId === memberRequestId) members.value = data || [];
}

async function loadRoundSummary() {
  const ledgerId = ledgerStore.activeLedgerId;
  const requestId = ++summaryRequestId;
  roundSummary.value = { amount: 0, count: 0, isActive: false };
  roundSummaryNote.value = "";

  if (!ledgerId) {
    roundLoading.value = false;
    return;
  }

  roundLoading.value = true;
  try {
    if (
      expenseStore.ledgerId !== ledgerId ||
      expenseStore.loadedLedgerId !== ledgerId
    ) {
      await expenseStore.setLedger(ledgerId);
    }
    if (requestId !== summaryRequestId) return;

    if (!supabase) {
      const eligible = expenseStore.expenses.filter(
        (expense) => expense.splits?.length,
      );
      roundSummary.value = {
        amount: eligible.reduce((sum, expense) => sum + expense.amount, 0),
        count: eligible.length,
        isActive: false,
      };
      roundSummaryNote.value = "目前以本機已分攤費用計算。";
      return;
    }

    const { data: batches, error: batchError } = await supabase
      .from("settlements")
      .select("id, total_amount, expense_count, status")
      .eq("ledger_id", ledgerId)
      .order("started_at", { ascending: false });
    if (batchError) throw batchError;
    if (requestId !== summaryRequestId) return;

    const activeBatch = (batches || []).find(
      (batch) => batch.status === "active",
    );
    if (activeBatch) {
      roundSummary.value = {
        amount: Number(activeBatch.total_amount),
        count: activeBatch.expense_count,
        isActive: true,
      };
      const settledBatchIds = (batches || []).map((batch) => batch.id);
      if (settledBatchIds.length) {
        const { data: settledExpenses, error: settledError } = await supabase
          .from("settlement_expenses")
          .select("expense_id")
          .in("settlement_id", settledBatchIds);
        if (settledError) throw settledError;
        const settledIds = new Set(
          (settledExpenses || []).map((row) => row.expense_id),
        );
        const nextCount = expenseStore.expenses.filter(
          (expense) => expense.splits?.length && !settledIds.has(expense.id),
        ).length;
        if (nextCount)
          roundSummaryNote.value = `${nextCount} 筆新費用將於本輪完成後列入下一輪。`;
      }
      return;
    }

    const settledBatchIds = (batches || []).map((batch) => batch.id);
    let settledIds = new Set();
    if (settledBatchIds.length) {
      const { data: settledExpenses, error: settledError } = await supabase
        .from("settlement_expenses")
        .select("expense_id")
        .in("settlement_id", settledBatchIds);
      if (settledError) throw settledError;
      settledIds = new Set(
        (settledExpenses || []).map((row) => row.expense_id),
      );
    }

    const eligible = expenseStore.expenses.filter(
      (expense) => expense.splits?.length && !settledIds.has(expense.id),
    );
    roundSummary.value = {
      amount: eligible.reduce((sum, expense) => sum + expense.amount, 0),
      count: eligible.length,
      isActive: false,
    };
    if (expenseStore.expenses.some((expense) => !expense.splits?.length)) {
      roundSummaryNote.value = "沒有分攤對象的舊費用不會計入本輪金額。";
    }
  } catch (error) {
    if (requestId === summaryRequestId) {
      const eligible = expenseStore.expenses.filter(
        (expense) => expense.splits?.length,
      );
      roundSummary.value = {
        amount: eligible.reduce((sum, expense) => sum + expense.amount, 0),
        count: eligible.length,
        isActive: false,
      };
      roundSummaryNote.value = "無法讀取結算批次，暫以所有已分攤費用估算。";
    }
  } finally {
    if (requestId === summaryRequestId) roundLoading.value = false;
  }
}

watch(() => ledgerStore.activeLedgerId, loadRoundSummary);
watch(() => ledgerStore.activeLedgerId, loadMembers, { immediate: true });
watch(
  [
    () => authStore.user?.user_metadata?.display_name,
    () => authStore.user?.user_metadata?.avatar_emoji,
  ],
  () => loadMembers(ledgerStore.activeLedgerId),
);
watch(() => expenseStore.totalAmount, loadRoundSummary);

onMounted(loadRoundSummary);

const recentExpenses = computed(() => expenseStore.recentExpenses.slice(0, 5));
const formatDate = (value) =>
  new Date(value).toLocaleDateString("zh-TW", {
    month: "numeric",
    day: "numeric",
  });

const loadApp = () => {
  window.location.reload();
};
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "歡迎使用分分"
      }}<button @click="loadApp" class="load-app-btn">🔄</button>
    </p>
    <h1>{{ ledgerStore.activeLedger ? "大家的帳本" : "先建立你的帳本" }}</h1>
  </section>

  <RouterLink
    v-if="!ledgerStore.activeLedger"
    class="notice ledger-home-notice"
    to="/ledgers"
  >
    <Layers3
      :size="18"
    />建立一個新帳本，或使用朋友的邀請連結加入帳本。<ArrowRight :size="16" />
  </RouterLink>

  <section v-else class="balance-card" aria-label="本輪分帳金額">
    <div class="balance-label">
      <CircleDollarSign :size="17" /> {{ roundLabel }}
    </div>
    <p class="balance-amount">
      {{ roundLoading ? "計算中…" : formattedTotal }}
    </p>
    <div class="balance-foot">
      <span
        >{{ expenseCountLabel }}
        <strong>{{ roundSummary.count }}</strong> 筆費用</span
      >
      <span>{{ roundSummary.isActive ? "結算進行中" : "尚未開始結算" }}</span>
    </div>
  </section>
  <p
    v-if="roundSummaryNote && ledgerStore.activeLedger"
    class="round-summary-note"
  >
    {{ roundSummaryNote }}
  </p>

  <div v-if="ledgerStore.activeLedger" class="quick-actions">
    <RouterLink class="quick-action" to="/expenses/new">
      <span class="quick-icon"><Plus :size="19" /></span>
      <span><strong>新增支出</strong><span>快速記下一筆</span></span>
    </RouterLink>
    <RouterLink class="quick-action" to="/settlements">
      <span class="quick-icon"><HandCoins :size="19" /></span>
      <span><strong>查看結算</strong><span>確認彼此的帳</span></span>
    </RouterLink>
  </div>

  <section>
    <div class="section-row">
      <h2>最近支出</h2>
      <div class="home-expense-links">
        <RouterLink class="section-link" to="/expenses"
          >全部 <ArrowRight :size="13"
        /></RouterLink>
        <RouterLink class="section-link" to="/expenses/new"
          >記一筆 <Plus :size="13"
        /></RouterLink>
      </div>
    </div>
    <p v-if="expenseStore.error" class="expense-error" role="alert">
      {{ expenseStore.error }}
    </p>
    <div v-if="expenseStore.isLoading" class="empty-state">
      正在從資料庫載入支出…
    </div>
    <div v-if="recentExpenses.length" class="expense-list">
      <article
        v-for="expense in recentExpenses"
        :key="expense.id"
        class="expense-item"
      >
        <span class="expense-symbol"><ReceiptText :size="19" /></span>
        <div class="expense-info">
          <strong>{{ expense.title }}</strong>
          <span
            >{{ payerName(expense) }} 付款・{{ expense.category }}・{{
              formatDate(expense.createdAt)
            }}</span
          >
        </div>
        <span class="expense-amount">{{
          currency.format(expense.amount)
        }}</span>
      </article>
    </div>
    <div v-else-if="!expenseStore.isLoading" class="empty-state">
      <ReceiptText :size="25" />
      <p>還沒有支出紀錄，新增第一筆開始分帳吧！</p>
    </div>
  </section>
</template>
