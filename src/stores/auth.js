import { defineStore } from "pinia";
import { supabase } from "../lib/supabase";

export const useAuthStore = defineStore("auth", {
  state: () => ({
    session: null,
    initialized: false,
    initializationError: "",
  }),
  getters: {
    user: (state) => state.session?.user ?? null,
  },
  actions: {
    async initialize() {
      if (this.initialized) return;
      if (!supabase) {
        this.initialized = true;
        return;
      }

      try {
        const { data, error } = await supabase.auth.getSession();
        if (error) this.initializationError = error.message;
        this.session = data?.session ?? null;

        supabase.auth.onAuthStateChange((_event, session) => {
          this.session = session;
        });
      } catch (error) {
        this.initializationError = error.message || "無法連線至 Supabase。";
      } finally {
        this.initialized = true;
      }
    },
    async signIn(email, password) {
      if (!supabase) throw new Error("尚未設定 Supabase 環境變數。");
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (error) throw error;
      this.session = data.session;
    },
    async signUp(email, password, displayName) {
      if (!supabase) throw new Error("尚未設定 Supabase 環境變數。");
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { display_name: displayName },
          emailRedirectTo: window.location.origin,
        },
      });
      if (error) throw error;
      this.session = data.session;
      return data;
    },
    async signOut() {
      if (!supabase) return;
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      this.session = null;
    },
  },
});
