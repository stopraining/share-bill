<template>
  <div v-if="!authStore.initialized" class="auth-loading" role="status">
    正在載入…
  </div>
  <AuthView v-else-if="!authStore.session" />
  <AppShell v-else />
</template>

<script setup>
import { onMounted } from "vue";
import AppShell from "./components/AppShell.vue";
import AuthView from "./views/AuthView.vue";
import { useAuthStore } from "./stores/auth";

const authStore = useAuthStore();

onMounted(() => authStore.initialize());
</script>
