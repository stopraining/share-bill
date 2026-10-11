<script setup>
import { ArrowRight, ReceiptText, ShieldCheck } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useAuthStore } from "../stores/auth";
import { supabase } from "../lib/supabase";

const authStore = useAuthStore();
const isRegistering = ref(false);
const displayName = ref("");
const email = ref("");
const password = ref("");
const isSubmitting = ref(false);
const errorMessage = ref("");
const successMessage = ref("");
const pageTitle = computed(() =>
  isRegistering.value ? "建立你的帳本" : "歡迎回來",
);

function toggleMode() {
  isRegistering.value = !isRegistering.value;
  errorMessage.value = "";
  successMessage.value = "";
}

async function submitAuthForm() {
  errorMessage.value = "";
  successMessage.value = "";
  isSubmitting.value = true;

  try {
    const normalizedEmail = email.value.trim().toLowerCase();
    if (isRegistering.value) {
      const result = await authStore.signUp(
        normalizedEmail,
        password.value,
        displayName.value.trim(),
      );
      if (!result.session) {
        successMessage.value = "註冊成功！請到信箱完成驗證，再回來登入。";
      }
    } else {
      await authStore.signIn(normalizedEmail, password.value);
    }
  } catch (error) {
    errorMessage.value = error.message || "發生錯誤，請稍後再試。";
  } finally {
    isSubmitting.value = false;
  }
}
</script>

<template>
  <main class="auth-screen">
    <section class="auth-card" aria-labelledby="auth-title">
      <div class="auth-brand-mark">
        <ReceiptText :size="25" :stroke-width="2.2" />
      </div>
      <p class="auth-brand-name">分分 <span>SHARE BILL</span></p>
      <p class="auth-eyebrow">一起記帳，分帳更簡單</p>
      <h1 id="auth-title">{{ pageTitle }}</h1>
      <p class="auth-description">
        {{
          isRegistering
            ? "註冊後即可開始記錄每一筆共同支出。"
            : "登入後繼續管理你的共同支出。"
        }}
      </p>

      <div v-if="!supabase" class="auth-message auth-error" role="alert">
        尚未設定 Supabase。請確認 .env.development 中的專案 URL 與 anon/public
        key，並重新啟動開發伺服器。
      </div>
      <div
        v-else-if="authStore.initializationError"
        class="auth-message auth-error"
        role="alert"
      >
        無法載入登入狀態：{{ authStore.initializationError }}
      </div>

      <form class="auth-form" @submit.prevent="submitAuthForm">
        <label v-if="isRegistering" class="auth-field">
          <span>顯示名稱</span>
          <input
            v-model="displayName"
            autocomplete="name"
            placeholder="例如：小明"
            type="text"
          />
        </label>
        <label class="auth-field">
          <span>電子郵件</span>
          <input
            v-model="email"
            autocomplete="email"
            placeholder="you@example.com"
            required
            type="email"
          />
        </label>
        <label class="auth-field">
          <span>密碼</span>
          <input
            v-model="password"
            :autocomplete="isRegistering ? 'new-password' : 'current-password'"
            minlength="6"
            placeholder="至少 6 個字元"
            required
            type="password"
          />
        </label>

        <p v-if="errorMessage" class="auth-message auth-error" role="alert">
          {{ errorMessage }}
        </p>
        <p
          v-if="successMessage"
          class="auth-message auth-success"
          role="status"
        >
          {{ successMessage }}
        </p>

        <button
          class="auth-submit"
          :disabled="isSubmitting || !supabase"
          type="submit"
        >
          {{ isSubmitting ? "處理中…" : isRegistering ? "建立帳號" : "登入" }}
          <ArrowRight v-if="!isSubmitting" :size="17" />
        </button>
      </form>

      <button class="auth-toggle" type="button" @click="toggleMode">
        {{ isRegistering ? "已經有帳號？登入" : "還沒有帳號？立即註冊" }}
      </button>
      <p class="auth-security">
        <ShieldCheck :size="15" />帳號由 Supabase 安全管理
      </p>
    </section>
  </main>
</template>

<style scoped>
.auth-screen {
  display: grid;
  min-height: 100vh;
  padding: 24px 18px;
  place-items: center;
  background: radial-gradient(
    circle at 50% 0%,
    #e5efe6 0,
    #f4f6f1 48%,
    #f4f6f1 100%
  );
}
.auth-card {
  width: min(100%, 420px);
  padding: 34px 28px 25px;
  border: 1px solid #edf0e9;
  border-radius: 28px;
  background: #fff;
  box-shadow: 0 18px 65px rgb(36 52 39 / 9%);
}
.auth-brand-mark {
  display: grid;
  width: 50px;
  height: 50px;
  margin: 0 auto 10px;
  place-items: center;
  border-radius: 17px;
  color: #fff;
  background: #27664b;
}
.auth-brand-name {
  margin: 0;
  text-align: center;
  font-size: 20px;
  font-weight: 750;
}
.auth-brand-name span {
  margin-left: 4px;
  color: #858b82;
  font-size: 10px;
  letter-spacing: 0.8px;
}
.auth-eyebrow {
  margin: 25px 0 7px;
  color: #858b82;
  font-size: 12px;
  text-align: center;
}
.auth-card h1 {
  text-align: center;
}
.auth-description {
  margin: 8px 0 23px;
  color: #747b72;
  font-size: 13px;
  text-align: center;
}
.auth-form {
  display: grid;
  gap: 15px;
}
.auth-field {
  display: grid;
  gap: 7px;
  color: #525a50;
  font-size: 12px;
  font-weight: 650;
}
.auth-field input {
  width: 100%;
  min-height: 48px;
  padding: 0 13px;
  border: 1px solid #e5eae2;
  border-radius: 13px;
  outline: none;
  background: #fbfcfa;
  font-size: 14px;
}
.auth-field input:focus {
  border-color: #80aa91;
  box-shadow: 0 0 0 3px rgb(39 102 75 / 9%);
}
.auth-submit {
  display: flex;
  min-height: 51px;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin-top: 3px;
  border: 0;
  border-radius: 14px;
  color: #fff;
  background: #27664b;
  font-weight: 700;
}
.auth-submit:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}
.auth-toggle {
  display: block;
  margin: 17px auto 0;
  padding: 7px 10px;
  border: 0;
  color: #27664b;
  background: transparent;
  font-size: 13px;
  font-weight: 650;
}
.auth-message {
  margin: 0;
  padding: 11px 12px;
  border-radius: 12px;
  font-size: 12px;
  line-height: 1.5;
}
.auth-error {
  color: #a23d30;
  background: #fff0ed;
}
.auth-success {
  color: #27664b;
  background: #edf6ed;
}
.auth-security {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
  margin: 20px 0 0;
  color: #8b9188;
  font-size: 11px;
}
:global(.auth-loading) {
  display: grid;
  min-height: 100vh;
  place-items: center;
  color: #27664b;
  font-size: 14px;
}
@media (max-width: 380px) {
  .auth-card {
    padding: 29px 21px 22px;
  }
}
</style>
