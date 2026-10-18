# Project Overview & Rules: Mobile-First Bill Splitter App (AA 制分帳手持應用)

## Project Goal

A mobile-first Web App / PWA designed for splitting bills easily among friends, supporting guest mode and cloud sync with Supabase.

## Core Features

1. **Expense Tracking**: Add, edit, and delete expenses (title, amount, payer, splitters, date, category).
2. **Settlement Algorithm**: Calculate individual net balances and suggest minimized transaction paths (who owes whom how much).
3. **User Auth & Sync**: Support Guest Mode (LocalStorage) and authenticated mode (Supabase Auth & Database sync).
4. **Member Management**: Manage group participants and their avatars.

## Tech Stack & Architecture

- **Framework**: Vue 3 (Composition API `<script setup>`, JavaScript / ES6+).
- **Build Tool**: Vite.
- **UI & Styling**: Tailwind CSS, Lucide Vue Next (Icons).
- **State Management**: Pinia.
- **Routing**: Vue Router.
- **Backend & Auth**: Supabase (`@supabase/supabase-js`).

## Design & UI System

- **Layout**: Mobile-first design. Max-width `480px` centered on desktop screens with a drop-shadow container.
- **Navigation**: Sticky bottom navigation bar (Views: Home/Expenses, Add Expense, Settlements, Profile/Members).
- **UX**: Touch-friendly large buttons, custom number keypad, card-style lists.
- **Language**: Traditional Chinese (`zh-TW`) for all UI strings and labels.

## Data Strategy

- Guest mode defaults to `localStorage`.
- Sync automatically to Supabase PostgreSQL when user is logged in.
