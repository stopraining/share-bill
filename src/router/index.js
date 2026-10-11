import { createRouter, createWebHistory } from "vue-router";

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: "/",
      name: "home",
      component: () => import("../views/HomeView.vue"),
    },
    {
      path: "/expenses/new",
      name: "new-expense",
      component: () => import("../views/NewExpenseView.vue"),
    },
    {
      path: "/expenses",
      name: "expenses",
      component: () => import("../views/ExpensesView.vue"),
    },
    {
      path: "/settlements",
      name: "settlements",
      component: () => import("../views/SettlementsView.vue"),
    },
    {
      path: "/members",
      name: "members",
      component: () => import("../views/MembersView.vue"),
    },
    {
      path: "/ledgers",
      name: "ledgers",
      component: () => import("../views/LedgersView.vue"),
    },
    { path: "/:pathMatch(.*)*", redirect: "/" },
  ],
});

export default router;
