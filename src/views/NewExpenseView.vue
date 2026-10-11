<script setup>
import { ArrowLeft, Plus } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useExpenseStore } from "../stores/expense";

const router = useRouter();
const expenseStore = useExpenseStore();
const title = ref("");
const amount = ref("");
const payer = ref("我");
const category = ref("餐飲");
const canSave = computed(
  () => title.value.trim().length > 0 && Number(amount.value) > 0,
);

function saveExpense() {
  if (!canSave.value) return;
  expenseStore.addExpense({
    title: title.value.trim(),
    amount: Number(amount.value),
    payer: payer.value.trim() || "我",
    category: category.value,
  });
  router.push("/");
}
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">週末小旅行</p>
    <h1>新增支出</h1>
  </section>

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
      <label for="expense-payer">付款人</label>
      <input
        id="expense-payer"
        v-model="payer"
        autocomplete="name"
        placeholder="誰先付款？"
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
    <button class="primary-button" :disabled="!canSave" type="submit">
      <Plus :size="18" />儲存支出
    </button>
  </form>
</template>
