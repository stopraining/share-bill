<script setup>
import { HandCoins, Info } from "lucide-vue-next";
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">週末小旅行</p>
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
