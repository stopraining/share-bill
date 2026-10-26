import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { supabase } from "../lib/supabase";

const ACTIVE_LEDGER_KEY = "share-bill-active-ledger";

export const useLedgerStore = defineStore("ledgers", () => {
  const ledgers = ref([]);
  const activeLedgerId = ref(localStorage.getItem(ACTIVE_LEDGER_KEY) || "");
  const isLoading = ref(false);
  const error = ref("");
  const activeLedger = computed(
    () =>
      ledgers.value.find((ledger) => ledger.id === activeLedgerId.value) ||
      null,
  );

  async function fetchLedgers() {
    if (!supabase) return;
    isLoading.value = true;
    error.value = "";
    try {
      const { data, error } = await supabase
        .from("ledgers")
        .select("id, name, description, currency, owner_id, created_at")
        .order("created_at", { ascending: false });
      if (error) throw error;
      ledgers.value = data || [];
      if (!ledgers.value.some((ledger) => ledger.id === activeLedgerId.value)) {
        setActiveLedger(ledgers.value[0]?.id || "");
      }
    } catch (err) {
      error.value = err.message || "無法載入帳本。";
    } finally {
      isLoading.value = false;
    }
  }

  function setActiveLedger(ledgerId) {
    activeLedgerId.value = ledgerId;
    if (ledgerId) localStorage.setItem(ACTIVE_LEDGER_KEY, ledgerId);
    else localStorage.removeItem(ACTIVE_LEDGER_KEY);
  }

  async function createLedger({ name, description = "", currency = "TWD" }) {
    if (!supabase) throw new Error("尚未連線 Supabase。");
    const { data: ledgerId, error } = await supabase.rpc("create_ledger", {
      p_name: name.trim(),
      p_description: description.trim(),
      p_currency: currency,
    });
    if (error) throw error;
    await fetchLedgers();
    const ledger = ledgers.value.find((item) => item.id === ledgerId);
    if (!ledger)
      throw new Error(
        "帳本已建立，但目前無法讀取。請確認帳本 SELECT RLS 政策。",
      );
    setActiveLedger(ledger.id);
    return ledger;
  }

  async function renameLedger(ledgerId, name) {
    if (!supabase) throw new Error("尚未連線 Supabase。");
    const normalizedName = String(name || "").trim();
    if (!normalizedName) throw new Error("帳本名稱不可空白。");

    const { data, error } = await supabase.rpc("rename_ledger", {
      p_ledger_id: ledgerId,
      p_name: normalizedName,
    });
    if (error) throw error;
    const ledger = ledgers.value.find((item) => item.id === ledgerId);
    if (!ledger) throw new Error("找不到帳本，請重新整理後再試。");
    ledger.name = normalizedName;
    return data;
  }

  async function acceptInvitation(token) {
    if (!supabase) throw new Error("尚未連線 Supabase。");
    const { data, error } = await supabase.rpc("accept_ledger_invitation", {
      p_token: token.trim(),
    });
    if (error) throw error;
    const ledgerId = typeof data === "string" ? data : data?.ledger_id;
    await fetchLedgers();
    if (ledgerId) setActiveLedger(ledgerId);
    return ledgerId;
  }

  async function inviteMember(email) {
    if (!supabase) throw new Error("尚未連線 Supabase。");
    if (!activeLedgerId.value) throw new Error("請先選擇一個帳本。");
    const { data, error } = await supabase.rpc("create_ledger_invitation", {
      p_ledger_id: activeLedgerId.value,
      p_email: email.trim().toLowerCase(),
    });
    if (error) throw error;
    return data;
  }

  async function deleteLedger(ledgerId) {
    if (!supabase) throw new Error("尚未連線 Supabase。");
    const ledger = ledgers.value.find((item) => item.id === ledgerId);
    if (!ledger) throw new Error("找不到要刪除的帳本，請重新整理後再試。");

    const { data, error } = await supabase
      .from("ledgers")
      .delete()
      .eq("id", ledgerId)
      .select("id")
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("刪除失敗，請確認你是此帳本的擁有者。");

    localStorage.removeItem(`share-bill-expenses:${ledgerId}`);
    localStorage.removeItem(`share-bill-expenses-migrated:${ledgerId}`);
    ledgers.value = ledgers.value.filter((item) => item.id !== ledgerId);
    if (activeLedgerId.value === ledgerId) {
      setActiveLedger(ledgers.value[0]?.id || "");
    }
  }

  return {
    ledgers,
    activeLedgerId,
    isLoading,
    error,
    activeLedger,
    fetchLedgers,
    setActiveLedger,
    createLedger,
    renameLedger,
    acceptInvitation,
    inviteMember,
    deleteLedger,
  };
});
