<script setup>
import { CirclePlus, Database, UsersRound } from "lucide-vue-next";
import { ref } from "vue";
import { supabase } from "../lib/supabase";
import { useAuthStore } from "../stores/auth";

const authStore = useAuthStore();
const isTesting = ref(false);
const testResult = ref("");
const testSucceeded = ref(false);

async function testSupabaseConnection() {
  if (!supabase) {
    testSucceeded.value = false;
    testResult.value =
      "找不到 Supabase 環境設定，請確認 .env.development 後重啟開發伺服器。";
    return;
  }

  isTesting.value = true;
  testResult.value = "";

  try {
    const { data, error } = await supabase.from("users").select("id").limit(1);
    if (error) throw error;

    testSucceeded.value = true;
    testResult.value =
      data.length === 0
        ? "連線成功，users 資料表可讀取；目前尚無個人資料列。請先在登入頁註冊帳號。"
        : "連線成功，users 資料表中已有個人資料列。";
  } catch (error) {
    testSucceeded.value = false;
    testResult.value = `測試失敗：${error.message}`;
  } finally {
    isTesting.value = false;
  }
}
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">週末小旅行</p>
    <h1>同行成員</h1>
  </section>

  <div class="notice">
    <UsersRound :size="17" />管理一起記帳的朋友。成員邀請與雲端同步可在 Supabase
    設定完成後啟用。
  </div>
  <section class="content-card">
    <article class="member-row">
      <span class="avatar" aria-hidden="true">🙂</span>
      <div class="member-meta">
        <strong>{{
          authStore.user?.user_metadata?.display_name || "已登入使用者"
        }}</strong>
        <span>{{ authStore.user?.email }}</span>
      </div>
      <span class="status-pill">你</span>
    </article>
    <button
      class="primary-button"
      :disabled="isTesting"
      type="button"
      style="margin-top: 18px"
      @click="testSupabaseConnection"
    >
      <Database :size="18" />{{ isTesting ? "測試中…" : "測試 Supabase 連線" }}
    </button>
    <p
      v-if="testResult"
      class="connection-result"
      :class="{ success: testSucceeded }"
      role="status"
    >
      {{ testResult }}
    </p>
    <button
      class="primary-button"
      disabled
      type="button"
      style="margin-top: 12px"
    >
      <CirclePlus :size="18" />邀請成員（即將推出）
    </button>
  </section>
</template>

<style scoped>
.connection-result {
  margin: 12px 2px 0;
  color: #b54735;
  font-size: 12px;
  line-height: 1.5;
}

.connection-result.success {
  color: #27664b;
}
</style>
