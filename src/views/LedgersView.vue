<script setup>
import {
  ArrowDownToLine,
  ArrowRight,
  BookOpen,
  Check,
  Copy,
  Pencil,
  Trash2,
  Plus,
  UsersRound,
} from "lucide-vue-next";
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "../stores/auth";
import { useLedgerStore } from "../stores/ledger";

const ledgerStore = useLedgerStore();
const authStore = useAuthStore();
const route = useRoute();
const router = useRouter();
const formMode = ref("");
const ledgerName = ref("");
const description = ref("");
const inviteEmail = ref("");
const invitationToken = ref("");
const invitationLink = ref("");
const joinToken = ref("");
const message = ref("");
const messageIsError = ref(false);
const isSubmitting = ref(false);
const deletingLedgerId = ref("");
const editingLedgerId = ref("");
const editedLedgerName = ref("");
const isSavingLedgerName = ref(false);
const copied = ref(false);
const isOwner = (ledger) => ledger.owner_id === authStore.user?.id;
const joinTokenPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const activeLedgerName = computed(() => ledgerStore.activeLedger?.name || "");

onMounted(async () => {
  await ledgerStore.fetchLedgers();
  const invite =
    typeof route.query.invite === "string" ? route.query.invite : "";
  if (invite && joinTokenPattern.test(invite)) {
    joinToken.value = invite;
    formMode.value = "join";
    await joinLedger();
  }
});

watch(
  () => ledgerStore.activeLedgerId,
  (id) => {
    if (id) {
      invitationToken.value = "";
      invitationLink.value = "";
    }
  },
);

function startCreate() {
  message.value = "";
  formMode.value = formMode.value === "create" ? "" : "create";
}

async function createLedger() {
  if (!ledgerName.value.trim()) return;
  isSubmitting.value = true;
  message.value = "";
  try {
    await ledgerStore.createLedger({
      name: ledgerName.value,
      description: description.value,
    });
    ledgerName.value = "";
    description.value = "";
    formMode.value = "";
    message.value = "帳本已建立並切換為目前帳本。";
  } catch (error) {
    message.value = error.message || "建立帳本失敗。";
  } finally {
    isSubmitting.value = false;
  }
}

async function createInvitation() {
  message.value = "";
  invitationToken.value = "";
  invitationLink.value = "";
  isSubmitting.value = true;
  try {
    const token = await ledgerStore.inviteMember(inviteEmail.value);
    invitationToken.value = token;
    invitationLink.value = `${window.location.origin}/ledgers?invite=${encodeURIComponent(token)}`;
    message.value =
      "邀請連結已建立；請傳給受邀者，對方需使用此電子郵件註冊或登入。";
  } catch (error) {
    message.value = error.message || "建立邀請失敗。";
  } finally {
    isSubmitting.value = false;
  }
}

async function copyInvitation() {
  try {
    await navigator.clipboard.writeText(invitationLink.value);
    copied.value = true;
    window.setTimeout(() => {
      copied.value = false;
    }, 1800);
  } catch {
    message.value = "瀏覽器無法自動複製，請手動複製下方連結。";
  }
}

async function deleteLedger(ledger) {
  const confirmed = window.confirm(
    `確定要刪除帳本「${ledger.name}」嗎？此操作無法復原，帳本內的支出、分攤和結算歷史也會一併刪除。`,
  );
  if (!confirmed || deletingLedgerId.value) return;

  deletingLedgerId.value = ledger.id;
  message.value = "";
  messageIsError.value = false;
  try {
    await ledgerStore.deleteLedger(ledger.id);
    message.value = `帳本「${ledger.name}」已刪除。`;
  } catch (error) {
    messageIsError.value = true;
    const details = [error.message, error.details, error.hint]
      .filter(Boolean)
      .join(" ");
    message.value = details.includes("settlement_expenses")
      ? "資料庫仍有結算歷史的刪除限制。請在 Supabase SQL Editor 執行 supabase/ledger_delete_migration.sql 後重試。"
      : error.message || "刪除帳本失敗。";
  } finally {
    deletingLedgerId.value = "";
  }
}

function startRenameLedger(ledger) {
  message.value = "";
  messageIsError.value = false;
  editingLedgerId.value = ledger.id;
  editedLedgerName.value = ledger.name;
}

function cancelRenameLedger() {
  editingLedgerId.value = "";
  editedLedgerName.value = "";
}

async function saveLedgerName(ledger) {
  const name = editedLedgerName.value.trim();
  if (!name || isSavingLedgerName.value) return;
  isSavingLedgerName.value = true;
  message.value = "";
  messageIsError.value = false;
  try {
    await ledgerStore.renameLedger(ledger.id, name);
    editingLedgerId.value = "";
    editedLedgerName.value = "";
    message.value = `帳本名稱已更新為「${name}」。`;
  } catch (error) {
    messageIsError.value = true;
    const details = [error.message, error.details, error.hint]
      .filter(Boolean)
      .join(" ");
    message.value = /rename_ledger|PGRST202/i.test(details)
      ? "資料庫尚未啟用帳本改名功能，請執行 supabase/ledger_rename_migration.sql。"
      : error.message || "修改帳本名稱失敗。";
  } finally {
    isSavingLedgerName.value = false;
  }
}

async function joinLedger() {
  const token = joinToken.value.trim();
  if (!joinTokenPattern.test(token)) {
    message.value = "請輸入有效的邀請代碼或完整邀請連結。";
    return;
  }
  isSubmitting.value = true;
  message.value = "";
  try {
    await ledgerStore.acceptInvitation(token);
    message.value = "已成功加入帳本。";
    joinToken.value = "";
    formMode.value = "";
    await router.replace({ path: "/ledgers" });
  } catch (error) {
    message.value =
      error.message || "加入帳本失敗。請確認邀請尚未過期，且登入的是受邀信箱。";
  } finally {
    isSubmitting.value = false;
  }
}

function selectLedger(ledgerId) {
  ledgerStore.setActiveLedger(ledgerId);
  router.push("/");
}

function parseInviteInput() {
  const input = joinToken.value.trim();
  if (input.includes("invite=")) {
    try {
      joinToken.value = new URL(input).searchParams.get("invite") || input;
    } catch {
      // Keep the entered text; validation will show a helpful error.
    }
  }
}
</script>

<template>
  <section class="page-heading">
    <p class="eyebrow">{{ authStore.user?.email }}</p>
    <h1>我的帳本</h1>
  </section>

  <div class="notice">
    <BookOpen
      :size="17"
    />建立多個帳本，或透過邀請連結加入朋友的帳本。每個帳本的支出彼此獨立。
  </div>

  <p v-if="ledgerStore.error" class="ledger-feedback error" role="alert">
    {{ ledgerStore.error }}
  </p>
  <div
    v-if="message"
    class="ledger-feedback"
    :class="{ error: messageIsError }"
    :role="messageIsError ? 'alert' : 'status'"
  >
    {{ message }}
  </div>

  <section class="ledger-actions">
    <button class="ledger-action" type="button" @click="startCreate">
      <span class="ledger-action-icon"><Plus :size="19" /></span>
      <span
        ><strong>建立新帳本</strong><small>開啟一個新的分帳群組</small></span
      >
      <ArrowRight :size="17" />
    </button>
    <button
      class="ledger-action"
      type="button"
      @click="
        formMode = formMode === 'join' ? '' : 'join';
        message = '';
      "
    >
      <span class="ledger-action-icon"><ArrowDownToLine :size="19" /></span>
      <span
        ><strong>加入帳本</strong
        ><small>使用朋友傳來的邀請連結或代碼</small></span
      >
      <ArrowRight :size="17" />
    </button>
  </section>

  <section v-if="formMode === 'create'" class="content-card ledger-form">
    <h2>建立新帳本</h2>
    <form @submit.prevent="createLedger">
      <div class="field">
        <label for="ledger-name">帳本名稱</label>
        <input
          id="ledger-name"
          v-model="ledgerName"
          maxlength="80"
          placeholder="例如：週末小旅行"
          required
        />
      </div>
      <div class="field">
        <label for="ledger-description">簡介（選填）</label>
        <input
          id="ledger-description"
          v-model="description"
          maxlength="200"
          placeholder="和誰、去哪裡"
        />
      </div>
      <button class="primary-button" :disabled="isSubmitting" type="submit">
        {{ isSubmitting ? "建立中…" : "建立帳本" }}
      </button>
    </form>
  </section>

  <section v-if="formMode === 'join'" class="content-card ledger-form">
    <h2>加入朋友的帳本</h2>
    <form
      @submit.prevent="
        parseInviteInput();
        joinLedger();
      "
    >
      <div class="field">
        <label for="invite-token">邀請連結或邀請代碼</label>
        <input
          id="invite-token"
          v-model="joinToken"
          autocomplete="off"
          placeholder="貼上朋友傳來的邀請連結"
          required
        />
      </div>
      <button class="primary-button" :disabled="isSubmitting" type="submit">
        {{ isSubmitting ? "加入中…" : "接受邀請" }}
      </button>
    </form>
  </section>

  <section
    v-if="ledgerStore.activeLedger && isOwner(ledgerStore.activeLedger)"
    class="content-card ledger-form"
  >
    <div class="section-row ledger-section-heading">
      <h2>邀請加入「{{ activeLedgerName }}」</h2>
      <UsersRound :size="18" />
    </div>
    <form @submit.prevent="createInvitation">
      <div class="field">
        <label for="invite-email">受邀者電子郵件</label>
        <input
          id="invite-email"
          v-model="inviteEmail"
          autocomplete="email"
          placeholder="friend@example.com"
          required
          type="email"
        />
      </div>
      <button class="primary-button" :disabled="isSubmitting" type="submit">
        {{ isSubmitting ? "產生邀請中…" : "產生邀請連結" }}
      </button>
    </form>
    <div v-if="invitationLink" class="invite-link-box">
      <label for="invite-link">邀請連結（僅限受邀信箱使用）</label>
      <div class="invite-copy-row">
        <input id="invite-link" :value="invitationLink" readonly />
        <button
          class="icon-button"
          type="button"
          :aria-label="copied ? '已複製' : '複製邀請連結'"
          @click="copyInvitation"
        >
          <Check v-if="copied" :size="17" /><Copy v-else :size="17" />
        </button>
      </div>
    </div>
  </section>

  <section>
    <div class="section-row">
      <h2>所有帳本</h2>
      <span class="ledger-count">{{ ledgerStore.ledgers.length }}</span>
    </div>
    <div v-if="ledgerStore.isLoading" class="empty-state">正在載入帳本…</div>
    <div v-else-if="!ledgerStore.ledgers.length" class="empty-state">
      <BookOpen :size="25" />
      <p>還沒有帳本，建立一個新帳本或使用邀請連結加入吧。</p>
    </div>
    <div v-else class="ledger-list">
      <div
        v-for="ledger in ledgerStore.ledgers"
        :key="ledger.id"
        class="ledger-card"
        :class="{ active: ledger.id === ledgerStore.activeLedgerId }"
      >
        <button
          class="ledger-card-select"
          type="button"
          :aria-label="`切換至帳本：${ledger.name}`"
          @click="selectLedger(ledger.id)"
        >
          <span class="ledger-avatar"><BookOpen :size="19" /></span>
          <span class="ledger-card-copy"
            ><strong>{{ ledger.name }}</strong
            ><small>{{
              ledger.description ||
              (isOwner(ledger) ? "你建立的帳本" : "朋友分享的帳本")
            }}</small></span
          >
          <span
            v-if="ledger.id === ledgerStore.activeLedgerId"
            class="status-pill"
            >目前使用</span
          >
          <ArrowRight v-else :size="17" class="ledger-chevron" />
        </button>
        <span v-if="isOwner(ledger)" class="ledger-card-actions">
          <button
            v-if="editingLedgerId !== ledger.id"
            class="ledger-edit-button"
            type="button"
            :aria-label="`修改帳本名稱：${ledger.name}`"
            @click="startRenameLedger(ledger)"
          >
            <Pencil :size="16" />
            <span>改名</span>
          </button>
          <button
            class="ledger-delete-button"
            type="button"
            :aria-label="`刪除帳本：${ledger.name}`"
            :disabled="deletingLedgerId === ledger.id"
            @click="deleteLedger(ledger)"
          >
            <Trash2 :size="17" />
            <span>{{
              deletingLedgerId === ledger.id ? "刪除中" : "刪除"
            }}</span>
          </button>
        </span>
        <form
          v-if="editingLedgerId === ledger.id"
          class="ledger-rename-form"
          @submit.prevent="saveLedgerName(ledger)"
        >
          <label :for="`ledger-name-${ledger.id}`">修改帳本名稱</label>
          <input
            :id="`ledger-name-${ledger.id}`"
            v-model="editedLedgerName"
            maxlength="80"
            required
            autofocus
          />
          <div class="ledger-rename-actions">
            <button
              class="expense-edit-button"
              type="button"
              :disabled="isSavingLedgerName"
              @click="cancelRenameLedger"
            >
              取消
            </button>
            <button
              class="primary-button"
              type="submit"
              :disabled="!editedLedgerName.trim() || isSavingLedgerName"
            >
              <Check :size="15" />{{
                isSavingLedgerName ? "儲存中…" : "儲存名稱"
              }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </section>
</template>
