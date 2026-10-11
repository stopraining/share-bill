-- Run in Supabase SQL Editor to enable the app's expense cloud sync.
-- This is safe for an existing expenses table and adds the payer display snapshot.
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers (id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  amount numeric(12, 2) not null check (amount > 0),
  currency text not null default 'TWD' check (currency ~ '^[A-Z]{3}$'),
  paid_by uuid not null references public.users (id) on delete restrict,
  created_by uuid not null references public.users (id) on delete restrict,
  payer_name text not null default '',
  category text not null default '其他',
  expense_date date not null default current_date,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.expenses
  add column if not exists payer_name text not null default '';

create index if not exists expenses_ledger_date_idx
  on public.expenses (ledger_id, expense_date desc);

alter table public.expenses enable row level security;

grant select, insert, update, delete on public.expenses to authenticated;

drop policy if exists "Ledger members can read expenses" on public.expenses;
create policy "Ledger members can read expenses"
  on public.expenses for select to authenticated
  using (public.is_ledger_member(ledger_id, auth.uid()));

drop policy if exists "Ledger members can create expenses" on public.expenses;
create policy "Ledger members can create expenses"
  on public.expenses for insert to authenticated
  with check (
    created_by = auth.uid()
    and paid_by = auth.uid()
    and public.is_ledger_member(ledger_id, auth.uid())
  );

drop policy if exists "Creators can update expenses" on public.expenses;
create policy "Creators can update expenses"
  on public.expenses for update to authenticated
  using (created_by = auth.uid() and public.is_ledger_member(ledger_id, auth.uid()))
  with check (created_by = auth.uid() and public.is_ledger_member(ledger_id, auth.uid()));

drop policy if exists "Creators can delete expenses" on public.expenses;
create policy "Creators can delete expenses"
  on public.expenses for delete to authenticated
  using (created_by = auth.uid() and public.is_ledger_member(ledger_id, auth.uid()));

notify pgrst, 'reload schema';
