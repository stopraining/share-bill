<script setup>
import { ArrowLeft, Check, Plus, UsersRound } from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink, useRouter } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";
import { supabase } from "../lib/supabase";

const router = useRouter();
const authStore = useAuthStore();
const expenseStore = useExpenseStore();
const ledgerStore = useLedgerStore();
const title = ref("");
const amount = ref("");
const members = ref([]);
const membersLoading = ref(false);
const membersError = ref("");
const payerUserId = ref("");
const splitUserIds = ref([]);
const category = ref("餐飲");
const isSaving = ref(false);
const saveError = ref("");
let memberRequestId = 0;
const memberLabel = (member) =>
  member.display_name || member.email?.split("@")[0] || "帳本成員";
const numberCurrency = new Intl.NumberFormat("zh-TW", {
  style: "currency",
  currency: "TWD",
  maximumFractionDigits: 2,
});
const canSave = computed(
  () =>
    title.value.trim().length > 0 &&
    Number(amount.value) > 0 &&
    Boolean(payerUserId.value) &&
    splitUserIds.value.length > 0 &&
    !membersLoading.value,
);
const perPersonShare = computed(() =>
  splitUserIds.value.length
    ? Number(amount.value || 0) / splitUserIds.value.length
    : 0,
);

async function loadLedgerMembers() {
  const ledgerId = ledgerStore.activeLedgerId;
  const requestId = ++memberRequestId;
  members.value = [];
  payerUserId.value = "";
  splitUserIds.value = [];
  membersError.value = "";
  if (!ledgerId || !supabase) {
    membersLoading.value = false;
    return;
  }

  membersLoading.value = true;
  try {
    const { data, error } = await supabase.rpc("list_ledger_members", {
      p_ledger_id: ledgerId,
    });
    if (error) throw error;
    if (requestId !== memberRequestId) return;
    members.value = data || [];
    const currentMember = members.value.find(
      (member) => member.user_id === authStore.user?.id,
    );
    payerUserId.value =
      currentMember?.user_id || members.value[0]?.user_id || "";
    splitUserIds.value = members.value.map((member) => member.user_id);
  } catch (error) {
    if (requestId === memberRequestId) {
      membersError.value = `無法載入帳本成員：${error.message}`;
    }
  } finally {
    if (requestId === memberRequestId) membersLoading.value = false;
  }
}

watch(() => ledgerStore.activeLedgerId, loadLedgerMembers);

onMounted(async () => {
  if (!ledgerStore.ledgers.length) await ledgerStore.fetchLedgers();
  await loadLedgerMembers();
});

async function saveExpense() {
  if (!canSave.value) return;
  isSaving.value = true;
  saveError.value = "";
  try {
    await expenseStore.addExpense({
      title: title.value.trim(),
      amount: Number(amount.value),
      payerUserId: payerUserId.value,
      splitUserIds: [...splitUserIds.value],
      category: category.value,
    });
    await router.push("/");
  } catch (error) {
    saveError.value = error.message || "支出儲存失敗，請稍後再試。";
  } finally {
    isSaving.value = false;
  }
}
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "尚未選擇帳本" }}
    </p>
    <h1>新增支出</h1>
  </section>

  <div v-if="!ledgerStore.activeLedger" class="empty-state">
    <p>新增支出前，請先建立或加入帳本。</p>
    <RouterLink class="section-link" to="/ledgers">前往帳本管理</RouterLink>
  </div>
  <template v-else>
    <div class="notice">
      <ArrowLeft :size="17" />填寫這筆消費資訊，之後可以再編輯分帳成員。
    </div>
    <form class="form-card" @submit.prevent="saveExpense">
      <div class="field">
        <label for="expense-title">支出項目</label>
        <input
          id="expense-title"
          v-model="title"
          autocomplete="off"
          placeholder="例如：晚餐、車票"
          required
        />
      </div>
      <div class="field">
        <label for="expense-amount">金額（NT$）</label>
        <input
          id="expense-amount"
          v-model="amount"
          class="amount-input"
          inputmode="decimal"
          min="1"
          max="9999999999.99"
          placeholder="0"
          required
          step="0.01"
          type="number"
        />
      </div>
      <p v-if="membersError" class="expense-error" role="alert">
        {{ membersError }}
      </p>
      <p v-else-if="membersLoading" class="member-state" role="status">
        正在載入帳本成員…
      </p>
      <p v-else-if="!members.length" class="expense-error" role="alert">
        此帳本沒有可選成員，請確認你已加入帳本。
      </p>

      <div v-if="members.length" class="field">
        <label for="expense-payer">付款人</label>
        <select id="expense-payer" v-model="payerUserId" required>
          <option
            v-for="member in members"
            :key="member.user_id"
            :value="member.user_id"
          >
            {{ memberLabel(member)
            }}{{ member.user_id === authStore.user?.id ? "（我）" : "" }}
          </option>
        </select>
      </div>

      <fieldset v-if="members.length" class="split-fieldset">
        <legend><UsersRound :size="16" />分攤費用的成員</legend>
        <p class="split-hint">
          勾選需要分攤的人，付款人可不在名單內。平均分攤若有零頭，系統會調整其中一位的金額以符合總額。
        </p>
        <label
          v-for="member in members"
          :key="member.user_id"
          class="split-member"
        >
          <input
            v-model="splitUserIds"
            type="checkbox"
            :value="member.user_id"
          />
          <span class="split-check"><Check :size="14" /></span>
          <span class="split-member-name">
            <strong
              >{{ memberLabel(member)
              }}{{
                member.user_id === authStore.user?.id ? "（我）" : ""
              }}</strong
            >
            <small>{{ member.email }}</small>
          </span>
          <span
            v-if="splitUserIds.includes(member.user_id) && amount"
            class="split-preview"
          >
            約 {{ numberCurrency.format(perPersonShare) }}
          </span>
        </label>
        <p v-if="!splitUserIds.length" class="split-validation" role="alert">
          請至少選擇一位分攤成員。
        </p>
      </fieldset>
      <div class="field">
        <label for="expense-category">分類</label>
        <select id="expense-category" v-model="category">
          <option>餐飲</option>
          <option>交通</option>
          <option>住宿</option>
          <option>購物</option>
          <option>其他</option>
        </select>
      </div>
      <p v-if="saveError" class="expense-error" role="alert">{{ saveError }}</p>
      <button
        class="primary-button"
        :disabled="!canSave || isSaving"
        type="submit"
      >
        <Plus :size="18" />{{ isSaving ? "儲存中…" : "儲存支出" }}
      </button>
    </form>
  </template>
</template>
