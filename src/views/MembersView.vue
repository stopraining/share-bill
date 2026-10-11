<script setup>
import { CirclePlus, RefreshCw, UsersRound } from "lucide-vue-next";
import { onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { supabase } from "../lib/supabase";
import { useAuthStore } from "../stores/auth";
import { useLedgerStore } from "../stores/ledger";

const authStore = useAuthStore();
const ledgerStore = useLedgerStore();
const members = ref([]);
const isLoadingMembers = ref(false);
const membersError = ref("");
let memberRequestId = 0;

const roleName = (role) =>
  ({
    owner: "擁有者",
    admin: "管理員",
    member: "成員",
  })[role] || "成員";

const memberInitial = (member) =>
  (member.display_name || member.email || "?").trim().slice(0, 1).toUpperCase();

const formatJoinedDate = (value) =>
  new Date(value).toLocaleDateString("zh-TW", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
  });

async function loadMembers() {
  const ledgerId = ledgerStore.activeLedgerId;
  const requestId = ++memberRequestId;
  membersError.value = "";
  members.value = [];

  if (!ledgerId || !supabase) {
    isLoadingMembers.value = false;
    return;
  }

  isLoadingMembers.value = true;
  try {
    const { data, error } = await supabase.rpc("list_ledger_members", {
      p_ledger_id: ledgerId,
    });
    if (error) throw error;
    if (requestId === memberRequestId) members.value = data || [];
  } catch (error) {
    if (requestId === memberRequestId) {
      membersError.value = `無法載入群組成員：${error.message}`;
    }
  } finally {
    if (requestId === memberRequestId) isLoadingMembers.value = false;
  }
}

watch(() => ledgerStore.activeLedgerId, loadMembers);

onMounted(async () => {
  if (!ledgerStore.ledgers.length) await ledgerStore.fetchLedgers();
  await loadMembers();
});
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">
      {{ ledgerStore.activeLedger?.name || "歡迎使用分分" }}
    </p>
    <h1>
      群組成員
      <span v-if="ledgerStore.activeLedgerId" class="member-count">{{
        members.length
      }}</span>
    </h1>
  </section>

  <div class="notice" v-if="ledgerStore.activeLedger">
    <UsersRound :size="17" />{{ ledgerStore.activeLedger.name }} 的帳本成員。
  </div>

  <section class="content-card">
    <div class="member-list-heading">
      <h2>所有成員</h2>
      <button
        class="refresh-button"
        :disabled="isLoadingMembers || !ledgerStore.activeLedgerId"
        type="button"
        @click="loadMembers"
      >
        <RefreshCw :size="15" :class="{ spinning: isLoadingMembers }" />重新整理
      </button>
    </div>

    <p v-if="!ledgerStore.activeLedgerId" class="member-state">
      請先建立或選取帳本，才能查看成員。
      <RouterLink class="section-link" to="/ledgers">前往帳本管理</RouterLink>
    </p>
    <p v-else-if="isLoadingMembers" class="member-state" role="status">
      正在載入成員…
    </p>
    <div
      v-else-if="membersError"
      class="member-state member-error"
      role="alert"
    >
      {{ membersError }}
      <p>
        若錯誤指出 RPC 不存在，請在 Supabase SQL Editor 執行
        <strong>supabase/members_migration.sql</strong>。
      </p>
    </div>
    <div v-else-if="!members.length" class="member-state">
      此帳本目前尚無成員資料。
    </div>
    <div v-else class="member-list">
      <article
        v-for="member in members"
        :key="member.user_id"
        class="member-row"
      >
        <span class="avatar member-avatar" aria-hidden="true">{{
          memberInitial(member)
        }}</span>
        <div class="member-meta">
          <strong>{{
            member.display_name || member.email.split("@")[0]
          }}</strong>
          <span
            >{{ member.email }}・加入於
            {{ formatJoinedDate(member.joined_at) }}</span
          >
        </div>
        <span class="status-pill">{{
          member.user_id === authStore.user?.id ? "你" : roleName(member.role)
        }}</span>
      </article>
    </div>

    <RouterLink class="primary-button" to="/ledgers" style="margin-top: 12px">
      <CirclePlus :size="18" />前往帳本管理邀請成員
    </RouterLink>
  </section>
</template>

<style scoped>
.member-count {
  display: inline-grid;
  min-width: 25px;
  height: 25px;
  margin-left: 4px;
  padding: 0 6px;
  place-items: center;
  border-radius: 99px;
  color: #27664b;
  background: #e8f1e9;
  font-size: 12px;
  vertical-align: 3px;
}

.member-list-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}

.refresh-button {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 7px 0 7px 8px;
  border: 0;
  color: #27664b;
  background: transparent;
  font-size: 11px;
}

.refresh-button:disabled {
  opacity: 0.55;
}

.member-state {
  margin: 12px 0 0;
  padding: 18px 12px;
  border-radius: 14px;
  color: #858b82;
  background: #f8faf7;
  font-size: 12px;
  line-height: 1.55;
  text-align: center;
}

.member-state p {
  margin: 8px 0 0;
  overflow-wrap: anywhere;
}

.member-state strong {
  font-weight: 650;
}

.member-error {
  color: #a23d30;
  background: #fff0ed;
}

.member-list {
  margin-top: 6px;
}

.member-avatar {
  color: #27664b;
  background: #e8f1e9;
  font-size: 15px;
  font-weight: 700;
}

.spinning {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
