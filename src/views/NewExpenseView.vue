<script setup>
import { ArrowLeft, Plus } from "lucide-vue-next";
import { computed, ref } from "vue";
import { RouterLink, useRouter } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";

const router = useRouter();
const authStore = useAuthStore();
const expenseStore = useExpenseStore();
const ledgerStore = useLedgerStore();
const title = ref("");
const amount = ref("");
const payer = ref(
  authStore.user?.user_metadata?.display_name || authStore.user?.email || "我",
);
const category = ref("餐飲");
const isSaving = ref(false);
const saveError = ref("");
const canSave = computed(
  () => title.value.trim().length > 0 && Number(amount.value) > 0,
);

async function saveExpense() {
  if (!canSave.value) return;
  isSaving.value = true;
  saveError.value = "";
  try {
    await expenseStore.addExpense({
      title: title.value.trim(),
      amount: Number(amount.value),
      payer: payer.value.trim() || "我",
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
          placeholder="0"
          required
          type="number"
        />
      </div>
      <div class="field">
        <label for="expense-payer">付款人（目前登入者）</label>
        <input
          id="expense-payer"
          v-model="payer"
          autocomplete="name"
          readonly
        />
      </div>
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
