import { defineStore } from "pinia";

const STORAGE_KEY = "share-bill-expenses";

function loadExpenses() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved ? JSON.parse(saved) : [];
  } catch {
    return [];
  }
}

export const useExpenseStore = defineStore("expenses", {
  state: () => ({ expenses: loadExpenses() }),
  getters: {
    totalAmount: (state) =>
      state.expenses.reduce((total, expense) => total + expense.amount, 0),
    recentExpenses: (state) =>
      [...state.expenses].sort((a, b) =>
        b.createdAt.localeCompare(a.createdAt),
      ),
  },
  actions: {
    addExpense(expense) {
      this.expenses.unshift({
        ...expense,
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
      });
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.expenses));
    },
  },
});
