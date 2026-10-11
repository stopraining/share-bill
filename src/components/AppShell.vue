<script setup>
import {
  ArrowRight,
  BookOpen,
  CirclePlus,
  HandCoins,
  Menu,
  LogOut,
  UsersRound,
  X,
  ReceiptText,
} from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { RouterLink, RouterView, useRoute } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useExpenseStore } from "../stores/expense";
import { useLedgerStore } from "../stores/ledger";
import { supabase } from "../lib/supabase";

const authStore = useAuthStore();
const ledgerStore = useLedgerStore();
const expenseStore = useExpenseStore();
const route = useRoute();
const isDrawerOpen = ref(false);
const drawerMembers = ref([]);
const drawerMembersLoading = ref(false);
const drawerMembersError = ref("");
let drawerMemberRequestId = 0;
const displayName = computed(
  () =>
    authStore.user?.user_metadata?.display_name ||
    authStore.user?.email ||
    "使用者",
);
const memberInitial = computed(() =>
  displayName.value.trim().slice(0, 1).toUpperCase(),
);

watch(
  () => route.fullPath,
  () => {
    isDrawerOpen.value = false;
  },
);

watch(
  [isDrawerOpen, () => ledgerStore.activeLedgerId],
  ([isOpen, ledgerId]) => {
    if (isOpen) loadDrawerMembers(ledgerId);
  },
);

async function loadDrawerMembers(ledgerId) {
  const requestId = ++drawerMemberRequestId;
  drawerMembers.value = [];
  drawerMembersError.value = "";
  if (!ledgerId || !supabase) {
    drawerMembersLoading.value = false;
    return;
  }

  drawerMembersLoading.value = true;
  try {
    const { data, error } = await supabase.rpc("list_ledger_members", {
      p_ledger_id: ledgerId,
    });
    if (error) throw error;
    if (requestId === drawerMemberRequestId) drawerMembers.value = data || [];
  } catch (error) {
    if (requestId === drawerMemberRequestId)
      drawerMembersError.value = error.message;
  } finally {
    if (requestId === drawerMemberRequestId) drawerMembersLoading.value = false;
  }
}

const drawerMemberName = (member) =>
  member.display_name || member.email?.split("@")[0] || "帳本成員";

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
      <button
        class="icon-button"
        type="button"
        :aria-label="isDrawerOpen ? '關閉側邊選單' : '開啟側邊選單'"
        :aria-expanded="isDrawerOpen"
        aria-controls="app-side-drawer"
        @click="isDrawerOpen = !isDrawerOpen"
      >
        <X v-if="isDrawerOpen" :size="19" />
        <Menu v-else :size="20" />
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
      <RouterLink class="nav-link" to="/ledgers" aria-label="帳本">
        <BookOpen :size="20" />
        <span>帳本</span>
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
    </nav>

    <div
      v-if="isDrawerOpen"
      class="drawer-backdrop"
      @click.self="isDrawerOpen = false"
    >
      <aside
        id="app-side-drawer"
        class="side-drawer"
        role="dialog"
        aria-modal="true"
        aria-label="帳號與成員選單"
      >
        <div class="drawer-heading">
          <div>
            <p class="drawer-eyebrow">目前帳本</p>
            <strong>{{
              ledgerStore.activeLedger?.name || "尚未選擇帳本"
            }}</strong>
          </div>
          <button
            class="icon-button drawer-close"
            type="button"
            aria-label="關閉選單"
            @click="isDrawerOpen = false"
          >
            <X :size="18" />
          </button>
        </div>

        <div class="drawer-profile">
          <span class="drawer-avatar" aria-hidden="true">{{
            memberInitial
          }}</span>
          <span class="drawer-profile-copy">
            <strong>{{ displayName }}</strong>
            <small>{{ authStore.user?.email }}</small>
          </span>
        </div>

        <p class="drawer-section-label">帳本資訊</p>
        <div class="drawer-members-heading">
          <span class="drawer-link-icon"><UsersRound :size="18" /></span>
          <strong>群組成員</strong>
          <span v-if="drawerMembers.length" class="drawer-member-count">{{
            drawerMembers.length
          }}</span>
        </div>
        <p v-if="drawerMembersLoading" class="drawer-members-state">
          正在載入成員…
        </p>
        <p
          v-else-if="drawerMembersError"
          class="drawer-members-state drawer-members-error"
        >
          {{ drawerMembersError }}
        </p>
        <p v-else-if="!ledgerStore.activeLedgerId" class="drawer-members-state">
          請先選擇帳本。
        </p>
        <p v-else-if="!drawerMembers.length" class="drawer-members-state">
          目前沒有成員資料。
        </p>
        <div v-else class="drawer-member-list">
          <div
            v-for="member in drawerMembers"
            :key="member.user_id"
            class="drawer-member-row"
          >
            <span class="drawer-member-avatar">{{
              drawerMemberName(member).slice(0, 1).toUpperCase()
            }}</span>
            <span class="drawer-member-copy">
              <strong>{{ drawerMemberName(member) }}</strong>
              <small>{{ member.email }}</small>
            </span>
            <span class="drawer-member-role">{{
              member.user_id === authStore.user?.id
                ? "你"
                : member.role === "owner"
                  ? "擁有者"
                  : member.role === "admin"
                    ? "管理員"
                    : "成員"
            }}</span>
          </div>
        </div>
        <RouterLink class="drawer-all-members" to="/members"
          >查看完整成員資訊 <ArrowRight :size="14"
        /></RouterLink>

        <RouterLink class="drawer-link" to="/ledgers">
          <span class="drawer-link-icon"><BookOpen :size="18" /></span>
          <span
            ><strong>管理帳本</strong
            ><small>切換、建立或邀請加入帳本</small></span
          >
          <ArrowRight :size="16" />
        </RouterLink>

        <button class="drawer-logout" type="button" @click="authStore.signOut">
          <LogOut :size="18" />登出
        </button>
      </aside>
    </div>
  </div>
</template>
