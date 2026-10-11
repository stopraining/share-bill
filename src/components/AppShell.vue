<script setup>
import {
  ArrowRight,
  CirclePlus,
  HandCoins,
  Layers3,
  LogOut,
  ReceiptText,
  UsersRound,
} from "lucide-vue-next";
import { onMounted, watch } from "vue";
import { RouterLink, RouterView } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";

const authStore = useAuthStore();
const ledgerStore = useLedgerStore();
const expenseStore = useExpenseStore();

watch(
  () => ledgerStore.activeLedgerId,
  (ledgerId) => {
    expenseStore.setLedger(ledgerId);
  },
  { immediate: true },
);

onMounted(() => ledgerStore.fetchLedgers());
</script>

<template>
  <div class="app-frame">
    <header class="app-header">
      <RouterLink class="brand" to="/" aria-label="分分首頁">
        <span class="brand-mark"
          ><ReceiptText :size="21" :stroke-width="2.2"
        /></span>
        <span class="brand-name"
          >分分 <span class="brand-caption">SHARE BILL</span></span
        >
      </RouterLink>
      <RouterLink
        class="ledger-switcher"
        to="/ledgers"
        :aria-label="ledgerStore.activeLedger?.name || '管理帳本'"
      >
        <Layers3 :size="17" />
        <span>{{ ledgerStore.activeLedger?.name || "選擇帳本" }}</span>
        <ArrowRight :size="14" />
      </RouterLink>
      <button
        class="icon-button"
        type="button"
        aria-label="登出"
        title="登出"
        @click="authStore.signOut"
      >
        <LogOut :size="18" />
      </button>
    </header>

    <main class="app-main">
      <RouterView />
    </main>

    <nav class="bottom-nav" aria-label="主要導覽">
      <RouterLink class="nav-link" to="/" aria-label="首頁">
        <ReceiptText :size="20" />
        <span>首頁</span>
      </RouterLink>
      <RouterLink
        class="nav-link add-link"
        to="/expenses/new"
        aria-label="新增支出"
      >
        <CirclePlus :size="23" />
        <span>記一筆</span>
      </RouterLink>
      <RouterLink class="nav-link" to="/settlements" aria-label="結算">
        <HandCoins :size="20" />
        <span>結算</span>
      </RouterLink>
      <RouterLink class="nav-link" to="/members" aria-label="成員">
        <UsersRound :size="20" />
        <span>成員</span>
      </RouterLink>
    </nav>
  </div>
</template>
