<script setup>
import {
  ArrowRight,
  CircleDollarSign,
  HandCoins,
  Plus,
  ReceiptText,
} from "lucide-vue-next";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useExpenseStore } from "../stores/expense";

const expenseStore = useExpenseStore();
const currency = new Intl.NumberFormat("zh-TW", {
  style: "currency",
  currency: "TWD",
  maximumFractionDigits: 0,
});
const formattedTotal = computed(() =>
  currency.format(expenseStore.totalAmount),
);
const recentExpenses = computed(() => expenseStore.recentExpenses.slice(0, 4));
const formatDate = (value) =>
  new Date(value).toLocaleDateString("zh-TW", {
    month: "numeric",
    day: "numeric",
  });
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">週末小旅行</p>
    <h1>大家的帳本</h1>
  </section>

  <section class="balance-card" aria-label="群組支出總覽">
    <div class="balance-label"><CircleDollarSign :size="17" /> 旅程總支出</div>
    <p class="balance-amount">{{ formattedTotal }}</p>
    <div class="balance-foot">
      <span
        >已記錄 <strong>{{ expenseStore.expenses.length }}</strong> 筆支出</span
      >
      <span>一起分帳更輕鬆</span>
    </div>
  </section>

  <div class="quick-actions">
    <RouterLink class="quick-action" to="/expenses/new">
      <button class="quick-icon"><Plus /></button>
      <span><strong>新增支出</strong><span>快速記下一筆</span></span>
    </RouterLink>
    <RouterLink class="quick-action" to="/settlements">
      <button class="quick-icon"><HandCoins /></button>
      <span><strong>查看結算</strong><span>確認彼此的帳</span></span>
    </RouterLink>
  </div>

  <section>
    <div class="section-row">
      <h2>最近支出</h2>
      <RouterLink class="section-link" to="/expenses/new"
        >記一筆 <ArrowRight :size="13"
      /></RouterLink>
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
            >{{ expense.payer }} 付款・{{ expense.category }}・{{
              formatDate(expense.createdAt)
            }}</span
          >
        </div>
        <span class="expense-amount">{{
          currency.format(expense.amount)
        }}</span>
      </article>
    </div>
    <div v-else class="empty-state">
      <ReceiptText :size="25" />
      <p>還沒有支出紀錄，新增第一筆開始分帳吧！</p>
    </div>
  </section>
</template>
