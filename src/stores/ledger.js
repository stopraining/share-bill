import { defineStore } from "pinia";
import { supabase } from "../lib/supabase";

const ACTIVE_LEDGER_KEY = "share-bill-active-ledger";

export const useLedgerStore = defineStore("ledgers", {
  state: () => ({
    ledgers: [],
    activeLedgerId: localStorage.getItem(ACTIVE_LEDGER_KEY) || "",
    isLoading: false,
    error: "",
  }),
  getters: {
    activeLedger: (state) =>
      state.ledgers.find((ledger) => ledger.id === state.activeLedgerId) ||
      null,
  },
  actions: {
    async fetchLedgers() {
      if (!supabase) return;
      this.isLoading = true;
      this.error = "";
      try {
        const { data, error } = await supabase
          .from("ledgers")
          .select("id, name, description, currency, owner_id, created_at")
          .order("created_at", { ascending: false });
        if (error) throw error;
        this.ledgers = data || [];
        if (!this.ledgers.some((ledger) => ledger.id === this.activeLedgerId)) {
          this.setActiveLedger(this.ledgers[0]?.id || "");
        }
      } catch (error) {
        this.error = error.message || "無法載入帳本。";
      } finally {
        this.isLoading = false;
      }
    },
    setActiveLedger(ledgerId) {
      this.activeLedgerId = ledgerId;
      if (ledgerId) localStorage.setItem(ACTIVE_LEDGER_KEY, ledgerId);
      else localStorage.removeItem(ACTIVE_LEDGER_KEY);
    },
    async createLedger({ name, description = "", currency = "TWD" }) {
      if (!supabase) throw new Error("尚未連線 Supabase。");
      const { data: ledgerId, error } = await supabase.rpc("create_ledger", {
        p_name: name.trim(),
        p_description: description.trim(),
        p_currency: currency,
      });
      if (error) throw error;
      await this.fetchLedgers();
      const ledger = this.ledgers.find((item) => item.id === ledgerId);
      if (!ledger)
        throw new Error(
          "帳本已建立，但目前無法讀取。請確認帳本 SELECT RLS 政策。",
        );
      this.setActiveLedger(ledger.id);
      return ledger;
    },
    async acceptInvitation(token) {
      if (!supabase) throw new Error("尚未連線 Supabase。");
      const { data, error } = await supabase.rpc("accept_ledger_invitation", {
        p_token: token.trim(),
      });
      if (error) throw error;
      const ledgerId = typeof data === "string" ? data : data?.ledger_id;
      await this.fetchLedgers();
      if (ledgerId) this.setActiveLedger(ledgerId);
      return ledgerId;
    },
    async inviteMember(email) {
      if (!supabase) throw new Error("尚未連線 Supabase。");
      if (!this.activeLedgerId) throw new Error("請先選擇一個帳本。");
      const { data, error } = await supabase.rpc("create_ledger_invitation", {
        p_ledger_id: this.activeLedgerId,
        p_email: email.trim().toLowerCase(),
      });
      if (error) throw error;
      return data;
    },
  },
});
