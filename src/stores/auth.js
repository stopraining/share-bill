import { defineStore } from "pinia";
import { computed, ref } from "vue";
import { supabase } from "../lib/supabase";

export const useAuthStore = defineStore("auth", () => {
  const session = ref(null);
  const initialized = ref(false);
  const initializationError = ref("");
  const user = computed(() => session.value?.user ?? null);

  async function initialize() {
    if (initialized.value) return;
    if (!supabase) {
      initialized.value = true;
      return;
    }

    try {
      const { data, error } = await supabase.auth.getSession();
      if (error) initializationError.value = error.message;
      session.value = data?.session ?? null;

      supabase.auth.onAuthStateChange((_event, authSession) => {
        session.value = authSession;
      });
    } catch (error) {
      initializationError.value = error.message || "無法連線至 Supabase。";
    } finally {
      initialized.value = true;
    }
  }

  async function signIn(email, password) {
    if (!supabase) throw new Error("尚未設定 Supabase 環境變數。");
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) throw error;
    session.value = data.session;
  }

  async function signUp(email, password, displayName) {
    if (!supabase) throw new Error("尚未設定 Supabase 環境變數。");
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: displayName },
        emailRedirectTo: `${window.location.origin}${window.location.pathname}${window.location.search}`,
      },
    });
    if (error) throw error;
    session.value = data.session;
    return data;
  }

  async function updateProfile({ displayName, avatarEmoji = "" }) {
    if (!supabase) throw new Error("尚未設定 Supabase 環境變數。");
    if (!user.value) throw new Error("登入狀態已失效，請重新登入後再試。");

    const normalizedName = displayName.trim();
    if (!normalizedName) throw new Error("使用者名稱不可空白。");
    if (normalizedName.length > 40)
      throw new Error("使用者名稱不可超過 40 個字。");

    const { data: previousProfile, error: readError } = await supabase
      .from("users")
      .select("display_name, avatar_emoji")
      .eq("id", user.value.id)
      .maybeSingle();
    if (readError) throw readError;
    if (!previousProfile) throw new Error("找不到使用者資料，無法更新名稱。");

    const { error: profileError } = await supabase
      .from("users")
      .update({
        display_name: normalizedName,
        avatar_emoji: avatarEmoji || "",
      })
      .eq("id", user.value.id);
    if (profileError) throw profileError;

    const { data, error } = await supabase.auth.updateUser({
      data: {
        display_name: normalizedName,
        avatar_emoji: avatarEmoji || null,
      },
    });
    if (error) {
      await supabase
        .from("users")
        .update({
          display_name: previousProfile.display_name,
          avatar_emoji: previousProfile.avatar_emoji || "",
        })
        .eq("id", user.value.id);
      throw error;
    }

    if (session.value && data.user) {
      session.value = { ...session.value, user: data.user };
    }
  }

  async function signOut() {
    if (!supabase) return;
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    session.value = null;
  }

  return {
    session,
    initialized,
    initializationError,
    user,
    initialize,
    signIn,
    signUp,
    updateProfile,
    signOut,
  };
});
