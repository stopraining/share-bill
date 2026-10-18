import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

// https://vite.dev/config/
export default defineConfig({
  base: "/share-bill/",
  plugins: [
    vue(),
    tailwindcss(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        id: "/share-bill/",
        name: "分分 Share Bill｜朋友一起記帳分帳",
        short_name: "分分",
        description: "和朋友一起記錄共同支出、分攤費用，快速整理轉帳與結算。",
        lang: "zh-TW",
        start_url: "/share-bill/",
        scope: "/share-bill/",
        display: "standalone",
        orientation: "portrait-primary",
        theme_color: "#27664b",
        background_color: "#f4f6f1",
        categories: ["finance", "lifestyle"],
        icons: [
          {
            src: "pwa-icon.svg",
            sizes: "192x192",
            type: "image/svg+xml",
            purpose: "any",
          },
          {
            src: "pwa-icon.svg",
            sizes: "512x512",
            type: "image/svg+xml",
            purpose: "any maskable",
          },
        ],
      },
    }),
  ],
});
