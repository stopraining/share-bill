<script setup>
import {
  ArrowRight,
  CircleDollarSign,
  Clock3,
  Check,
  HandCoins,
  Info,
  ReceiptText,
  RotateCw,
  Send,
  UsersRound,
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
const membersLoading = ref(false);
const membersError = ref("");
const settlementSessions = ref([]);
const settlementTransfers = ref([]);
const settlementExpenseSnapshots = ref([]);
const accountedExpenseIds = ref(new Set());
const settlementError = ref("");
const isStartingSettlement = ref(false);
const updatingTransferId = ref("");
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
const memberAvatar = (userId) => {
  const member = memberMap.value.get(userId);
  return (
    member?.avatar_emoji || memberName(userId).trim().slice(0, 1).toUpperCase()
  );
};
const expenses = computed(() => expenseStore.recentExpenses);
const pendingExpenses = computed(() =>
  expenses.value.filter(
    (expense) => !accountedExpenseIds.value.has(expense.id),
  ),
);
const candidateExpenses = computed(() =>
  pendingExpenses.value.filter((expense) => expense.splits?.length),
);
const incompleteExpenses = computed(() =>
  pendingExpenses.value.filter((expense) => !expense.splits?.length),
);
const totalSpend = computed(() =>
  activeSettlement.value
    ? Number(activeSettlement.value.total_amount)
    : candidateExpenses.value.reduce(
        (total, expense) => total + expense.amount,
        0,
      ),
);
const currentSettlement = computed(
  () =>
    settlementSessions.value.find(
      (settlement) => settlement.status === "active",
    ) || null,
);
const activeSettlement = currentSettlement;
const completedSettlements = computed(() =>
  settlementSessions.value.filter(
    (settlement) => settlement.status === "completed",
  ),
);
const activeTransfers = computed(() =>
  settlementTransfers.value.filter(
    (transfer) => transfer.settlement_id === activeSettlement.value?.id,
  ),
);
const currentBatchExpenseCount = computed(
  () => activeSettlement.value?.expense_count || candidateExpenses.value.length,
);

const balances = computed(() => {
  const centsByMember = new Map(
    members.value.map((member) => [member.user_id, 0]),
  );

  for (const expense of candidateExpenses.value) {
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
  settlementError.value = "";
  settlementSessions.value = [];
  settlementTransfers.value = [];
  settlementExpenseSnapshots.value = [];
  accountedExpenseIds.value = new Set();

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
    const [memberResult, sessionResult, transferResult, expenseResult] =
      await Promise.all([
        supabase.rpc("list_ledger_members", { p_ledger_id: ledgerId }),
        supabase
          .from("settlements")
          .select(
            "id, ledger_id, started_by, status, total_amount, expense_count, started_at, completed_at",
          )
          .eq("ledger_id", ledgerId)
          .order("started_at", { ascending: false }),
        supabase
          .from("settlement_transfers")
          .select(
            "id, settlement_id, payer_id, payee_id, amount, status, paid_at, confirmed_at",
          )
          .order("created_at", { ascending: true }),
        supabase
          .from("settlement_expenses")
          .select(
            "settlement_id, expense_id, expenses(title, amount, category)",
          ),
      ]);
    if (memberResult.error) throw memberResult.error;
    if (sessionResult.error) throw sessionResult.error;
    if (transferResult.error) throw transferResult.error;
    if (expenseResult.error) throw expenseResult.error;
    if (requestId === dataRequestId) {
      members.value = memberResult.data || [];
      settlementSessions.value = sessionResult.data || [];
      const sessionIds = new Set(
        settlementSessions.value.map((session) => session.id),
      );
      settlementTransfers.value = (transferResult.data || []).filter(
        (transfer) => sessionIds.has(transfer.settlement_id),
      );
      settlementExpenseSnapshots.value = (expenseResult.data || []).filter(
        (row) => sessionIds.has(row.settlement_id),
      );
      accountedExpenseIds.value = new Set(
        settlementExpenseSnapshots.value.map((row) => row.expense_id),
      );
    }
  } catch (error) {
    if (requestId === dataRequestId) {
      membersError.value = error.message;
      settlementError.value = `無法載入結算狀態：${error.message}`;
    }
  } finally {
    if (requestId === dataRequestId) membersLoading.value = false;
  }
}

async function startSettlement() {
  if (
    activeSettlement.value ||
    !candidateExpenses.value.length ||
    isStartingSettlement.value
  )
    return;
  isStartingSettlement.value = true;
  settlementError.value = "";
  try {
    const { error } = await supabase.rpc("start_ledger_settlement", {
      p_ledger_id: ledgerStore.activeLedgerId,
    });
    if (error) throw error;
    await loadLedgerData();
  } catch (error) {
    settlementError.value = error.message || "無法開始結算。";
  } finally {
    isStartingSettlement.value = false;
  }
}

async function runTransferAction(transfer, action) {
  if (updatingTransferId.value) return;
  updatingTransferId.value = transfer.id;
  settlementError.value = "";
  const rpcName =
    action === "paid"
      ? "mark_settlement_transfer_paid"
      : "confirm_settlement_transfer_received";
  try {
    const { error } = await supabase.rpc(rpcName, {
      p_transfer_id: transfer.id,
    });
    if (error) throw error;
    await loadLedgerData();
  } catch (error) {
    settlementError.value = error.message || "更新轉帳狀態失敗。";
  } finally {
    updatingTransferId.value = "";
  }
}

const transferStatus = (status) =>
  ({
    pending: "待付款人匯款",
    paid: "待收款人確認",
    confirmed: "已確認收款",
  })[status] || status;

const formatDate = (value) =>
  new Date(value).toLocaleDateString("zh-TW", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
  });

watch(() => ledgerStore.activeLedgerId, loadLedgerData);
watch(
  [
    () => authStore.user?.user_metadata?.display_name,
    () => authStore.user?.user_metadata?.avatar_emoji,
  ],
  loadLedgerData,
);
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
    <p v-if="settlementError" class="expense-error" role="alert">
      {{ settlementError }}。若是結算資料庫函式或資料表不存在，請執行
      <strong>supabase/settlements_migration.sql</strong>。
    </p>
    <div v-if="incompleteExpenses.length" class="notice incomplete-notice">
      <Info :size="17" />有
      {{ incompleteExpenses.length }}
      筆費用沒有分攤明細，無法納入結算；請至「瀏覽所有費用」檢視。
    </div>
    <div
      v-if="activeSettlement && candidateExpenses.length"
      class="notice next-round-notice"
    >
      <Info :size="17" />目前結算開始後新增的
      {{ candidateExpenses.length }} 筆費用會留到下一輪，不會改變本輪轉帳金額。
    </div>

    <div class="settlement-summary-grid">
      <article class="settlement-summary-card">
        <span class="settlement-summary-icon"
          ><CircleDollarSign :size="18"
        /></span>
        <small>{{ activeSettlement ? "本輪結算金額" : "待結算支出" }}</small>
        <strong>{{ currency.format(totalSpend) }}</strong>
      </article>
      <article class="settlement-summary-card">
        <span class="settlement-summary-icon"><ReceiptText :size="18" /></span>
        <small>費用項目</small>
        <strong>{{ currentBatchExpenseCount }} 筆</strong>
      </article>
    </div>

    <section>
      <div class="section-row settlement-section-row">
        <h2>{{ activeSettlement ? "本輪轉帳狀態" : "待結算預覽" }}</h2>
        <span class="settlement-count"
          >{{
            activeSettlement ? activeTransfers.length : transfers.length
          }}
          筆轉帳</span
        >
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
      <div v-else-if="activeSettlement" class="active-settlement-panel">
        <div class="active-settlement-heading">
          <span class="active-settlement-icon"><Clock3 :size="18" /></span>
          <span
            ><strong>結算進行中</strong
            ><small
              >開始於 {{ formatDate(activeSettlement.started_at) }}・本輪包含
              {{ activeSettlement.expense_count }} 筆費用</small
            ></span
          >
          <div
            v-if="
              settlementExpenseSnapshots.some(
                (row) => row.settlement_id === activeSettlement.id,
              )
            "
            class="active-expense-snapshot"
          >
            <strong>本輪費用快照</strong>
            <span
              v-for="row in settlementExpenseSnapshots.filter(
                (item) => item.settlement_id === activeSettlement.id,
              )"
              :key="row.expense_id"
            >
              {{ row.expenses?.title || "費用紀錄" }}・{{
                currency.format(row.expenses?.amount || 0)
              }}
            </span>
          </div>
        </div>
        <article
          v-for="transfer in activeTransfers"
          :key="transfer.id"
          class="settlement-transfer-row"
        >
          <div class="settlement-transfer-people">
            <span class="transfer-person debtor"
              ><span class="transfer-avatar" aria-hidden="true">{{
                memberAvatar(transfer.payer_id)
              }}</span
              ><strong>{{ memberName(transfer.payer_id) }}</strong></span
            >
            <span class="transfer-direction"
              ><strong>{{ currency.format(transfer.amount) }}</strong
              ><ArrowRight :size="16"
            /></span>
            <span class="transfer-person creditor"
              ><span class="transfer-avatar" aria-hidden="true">{{
                memberAvatar(transfer.payee_id)
              }}</span
              ><strong>{{ memberName(transfer.payee_id) }}</strong></span
            >
          </div>
          <div class="settlement-transfer-footer">
            <span
              class="transfer-status-pill"
              :class="`is-${transfer.status}`"
              >{{ transferStatus(transfer.status) }}</span
            >
            <button
              v-if="
                transfer.status === 'pending' &&
                transfer.payer_id === authStore.user?.id
              "
              class="transfer-action-button"
              :disabled="updatingTransferId === transfer.id"
              type="button"
              @click="runTransferAction(transfer, 'paid')"
            >
              <Send :size="14" />{{
                updatingTransferId === transfer.id ? "更新中…" : "我已匯款"
              }}
            </button>
            <button
              v-else-if="
                transfer.status === 'paid' &&
                transfer.payee_id === authStore.user?.id
              "
              class="transfer-action-button"
              :disabled="updatingTransferId === transfer.id"
              type="button"
              @click="runTransferAction(transfer, 'confirmed')"
            >
              <Check :size="15" />{{
                updatingTransferId === transfer.id ? "更新中…" : "確認收到"
              }}
            </button>
            <span
              v-else-if="transfer.status === 'paid'"
              class="transfer-waiting"
              >等待 {{ memberName(transfer.payee_id) }} 確認收款</span
            >
            <span
              v-else-if="transfer.status === 'pending'"
              class="transfer-waiting"
              >等待 {{ memberName(transfer.payer_id) }} 匯款</span
            >
            <span v-else class="transfer-confirmed"
              ><Check :size="14" />收款已確認</span
            >
          </div>
        </article>
        <p class="settlement-history-note">
          每筆轉帳由付款人標記已匯款，再由收款人確認。全部確認後，本輪會自動結束。
        </p>
      </div>
      <div
        v-else-if="!candidateExpenses.length"
        class="empty-state settlement-empty"
      >
        <HandCoins :size="25" />
        <p>
          {{
            incompleteExpenses.length
              ? "目前尚無可結算的費用；舊費用缺少分攤資料，請在費用紀錄新增調整項目。"
              : completedSettlements.length
                ? "目前沒有新費用，過往結算已保留在下方歷史紀錄。"
                : "目前沒有待結算的款項"
          }}
        </p>
        <RouterLink
          v-if="!incompleteExpenses.length"
          class="section-link"
          to="/expenses/new"
          >新增第一筆費用</RouterLink
        >
      </div>
      <div v-else-if="!transfers.length" class="settled-banner">
        <span class="settled-check">✓</span>
        <span
          ><strong>目前不需要轉帳</strong
          ><small>仍可建立結算批次封存這些費用。</small></span
        >
      </div>
      <div v-else class="transfer-list">
        <article
          v-for="(transfer, index) in transfers"
          :key="`${transfer.from.user_id}-${transfer.to.user_id}-${index}`"
          class="transfer-card"
        >
          <span class="transfer-person debtor"
            ><span class="transfer-avatar" aria-hidden="true">{{
              memberAvatar(transfer.from.user_id)
            }}</span
            ><strong>{{ memberName(transfer.from.user_id) }}</strong></span
          >
          <span class="transfer-direction"
            ><span>{{ currency.format(transfer.amount) }}</span
            ><ArrowRight :size="17"
          /></span>
          <span class="transfer-person creditor"
            ><span class="transfer-avatar" aria-hidden="true">{{
              memberAvatar(transfer.to.user_id)
            }}</span
            ><strong>{{ memberName(transfer.to.user_id) }}</strong></span
          >
        </article>
      </div>
      <button
        v-if="candidateExpenses.length && !activeSettlement"
        class="primary-button start-settlement-button"
        :disabled="
          isStartingSettlement || membersLoading || expenseStore.isLoading
        "
        type="button"
        @click="startSettlement"
      >
        <RotateCw :size="17" />{{
          isStartingSettlement ? "正在建立結算…" : "開始本輪結算並封存費用"
        }}
      </button>
      <p
        v-if="candidateExpenses.length && !activeSettlement"
        class="settlement-history-note"
      >
        開始後，這
        {{ candidateExpenses.length }}
        筆費用會保留為固定快照；之後新增的費用會自動列入下一輪。
      </p>
    </section>

    <section v-if="!activeSettlement">
      <div class="section-row settlement-section-row">
        <h2>下一輪收付預覽</h2>
        <UsersRound :size="17" />
      </div>
      <div v-if="balances.length" class="content-card settlement-balances">
        <article
          v-for="member in balances"
          :key="member.user_id"
          class="settlement-balance-row"
        >
          <span class="transfer-avatar" aria-hidden="true">{{
            memberAvatar(member.user_id)
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

    <section v-if="completedSettlements.length">
      <div class="section-row settlement-section-row">
        <h2>過往結算</h2>
        <span class="settlement-count"
          >{{ completedSettlements.length }} 輪</span
        >
      </div>
      <div class="settlement-history-list">
        <details
          v-for="settlement in completedSettlements"
          :key="settlement.id"
          class="settlement-history-card"
        >
          <summary>
            <span class="settlement-history-icon"><Check :size="17" /></span>
            <span class="settlement-history-summary"
              ><strong>{{ formatDate(settlement.started_at) }} 結算</strong
              ><small
                >{{ settlement.expense_count }} 筆費用・{{
                  currency.format(settlement.total_amount)
                }}</small
              ></span
            >
            <span class="transfer-status-pill is-confirmed">已完成</span>
          </summary>
          <div class="settlement-history-detail">
            <p>
              完成於
              {{ formatDate(settlement.completed_at || settlement.started_at) }}
            </p>
            <div
              v-for="row in settlementExpenseSnapshots.filter(
                (item) => item.settlement_id === settlement.id,
              )"
              :key="row.expense_id"
              class="settlement-history-transfer"
            >
              <span
                >{{ row.expenses?.title || "費用紀錄" }}・{{
                  row.expenses?.category || "其他"
                }}</span
              >
              <strong>{{ currency.format(row.expenses?.amount || 0) }}</strong>
            </div>
            <article
              v-for="transfer in settlementTransfers.filter(
                (item) => item.settlement_id === settlement.id,
              )"
              :key="transfer.id"
              class="settlement-history-transfer"
            >
              <span
                >{{ memberName(transfer.payer_id) }} →
                {{ memberName(transfer.payee_id) }}</span
              >
              <strong>{{ currency.format(transfer.amount) }}</strong>
            </article>
            <p
              v-if="
                !settlementTransfers.some(
                  (item) => item.settlement_id === settlement.id,
                )
              "
              class="settlement-history-note"
            >
              本輪不需要轉帳。
            </p>
          </div>
        </details>
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
