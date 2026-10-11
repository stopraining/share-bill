<script setup>
import { HandCoins, Info } from "lucide-vue-next";
import { useLedgerStore } from "../stores/ledger";

const ledgerStore = useLedgerStore();
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "歡迎使用分分" }}
    </p>
    <h1>結算明細</h1>
  </section>

  <div class="notice">
    <Info :size="17" />記錄支出並加入同行成員後，這裡會整理每個人的收付金額。
  </div>
  <section class="content-card">
    <div class="empty-state">
      <HandCoins :size="27" />
      <p>目前沒有待結算的款項</p>
    </div>
  </section>
</template>
