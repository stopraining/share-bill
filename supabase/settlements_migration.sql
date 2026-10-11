-- Run in Supabase Dashboard → SQL Editor to enable settlement batches.
-- Requires the ledger/member and expense/split schema migrations to have been run first.
-- A settlement freezes its expense membership and suggested transfers. Expenses already
-- included in a settlement must be corrected with a new adjustment expense so history stays auditable.

create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers (id) on delete cascade,
  started_by uuid not null references public.users (id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'completed')),
  total_amount numeric(12, 2) not null default 0 check (total_amount >= 0),
  expense_count integer not null default 0 check (expense_count >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index if not exists settlements_one_active_per_ledger_idx
  on public.settlements (ledger_id) where status = 'active';
create index if not exists settlements_ledger_started_idx
  on public.settlements (ledger_id, started_at desc);

create table if not exists public.settlement_expenses (
  settlement_id uuid not null references public.settlements (id) on delete cascade,
  expense_id uuid not null references public.expenses (id) on delete restrict,
  primary key (settlement_id, expense_id),
  unique (expense_id)
);

create table if not exists public.settlement_transfers (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.settlements (id) on delete cascade,
  payer_id uuid not null references public.users (id) on delete restrict,
  payee_id uuid not null references public.users (id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'confirmed')),
  paid_at timestamptz,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  check (payer_id <> payee_id)
);

create index if not exists settlement_transfers_settlement_idx
  on public.settlement_transfers (settlement_id);

alter table public.settlements enable row level security;
alter table public.settlement_expenses enable row level security;
alter table public.settlement_transfers enable row level security;

grant select on public.settlements, public.settlement_expenses, public.settlement_transfers to authenticated;

drop policy if exists "Ledger members can read settlements" on public.settlements;
create policy "Ledger members can read settlements"
  on public.settlements for select to authenticated
  using (public.is_ledger_member(ledger_id, auth.uid()));

drop policy if exists "Ledger members can read settlement expenses" on public.settlement_expenses;
create policy "Ledger members can read settlement expenses"
  on public.settlement_expenses for select to authenticated
  using (
    exists (
      select 1 from public.settlements s
      where s.id = settlement_id and public.is_ledger_member(s.ledger_id, auth.uid())
    )
  );

drop policy if exists "Ledger members can read settlement transfers" on public.settlement_transfers;
create policy "Ledger members can read settlement transfers"
  on public.settlement_transfers for select to authenticated
  using (
    exists (
      select 1 from public.settlements s
      where s.id = settlement_id and public.is_ledger_member(s.ledger_id, auth.uid())
    )
  );

create or replace function public.start_ledger_settlement(p_ledger_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_settlement_id uuid;
  v_total numeric(12, 2);
  v_expense_count integer;
begin
  if v_user_id is null then
    raise exception '請先登入後開始結算。';
  end if;
  if not public.is_ledger_member(p_ledger_id, v_user_id) then
    raise exception '只有帳本成員可以開始結算。';
  end if;
  if exists (select 1 from public.settlements s where s.ledger_id = p_ledger_id and s.status = 'active') then
    raise exception '此帳本已有尚未完成的結算，請先完成或處理目前結算。';
  end if;

  select coalesce(sum(e.amount), 0)::numeric(12, 2), count(*)::integer
  into v_total, v_expense_count
  from public.expenses e
  where e.ledger_id = p_ledger_id
    and exists (select 1 from public.expense_splits sp where sp.expense_id = e.id)
    and not exists (select 1 from public.settlement_expenses se where se.expense_id = e.id);

  if v_expense_count = 0 then
    raise exception '目前沒有尚未結算且具有分攤明細的費用。';
  end if;

  insert into public.settlements (ledger_id, started_by, total_amount, expense_count)
  values (p_ledger_id, v_user_id, v_total, v_expense_count)
  returning id into v_settlement_id;

  insert into public.settlement_expenses (settlement_id, expense_id)
  select v_settlement_id, e.id
  from public.expenses e
  where e.ledger_id = p_ledger_id
    and exists (select 1 from public.expense_splits sp where sp.expense_id = e.id)
    and not exists (select 1 from public.settlement_expenses se where se.expense_id = e.id);

  -- Build minimal transfers by intersecting ordered debtor and creditor cent ranges.
  with member_net as (
    select lm.user_id,
      coalesce(paid.total_cents, 0) - coalesce(share.total_cents, 0) as net_cents
    from public.ledger_members lm
    left join lateral (
      select sum(round(e.amount * 100))::bigint as total_cents
      from public.settlement_expenses se
      join public.expenses e on e.id = se.expense_id
      where se.settlement_id = v_settlement_id and e.paid_by = lm.user_id
    ) paid on true
    left join lateral (
      select sum(round(sp.amount * 100))::bigint as total_cents
      from public.settlement_expenses se
      join public.expense_splits sp on sp.expense_id = se.expense_id
      where se.settlement_id = v_settlement_id and sp.user_id = lm.user_id
    ) share on true
    where lm.ledger_id = p_ledger_id
  ), debtors as (
    select user_id, -net_cents as cents,
      coalesce(sum(-net_cents) over (order by -net_cents desc, user_id rows between unbounded preceding and 1 preceding), 0)::bigint as range_start,
      sum(-net_cents) over (order by -net_cents desc, user_id)::bigint as range_end
    from member_net where net_cents < 0
  ), creditors as (
    select user_id, net_cents as cents,
      coalesce(sum(net_cents) over (order by net_cents desc, user_id rows between unbounded preceding and 1 preceding), 0)::bigint as range_start,
      sum(net_cents) over (order by net_cents desc, user_id)::bigint as range_end
    from member_net where net_cents > 0
  )
  insert into public.settlement_transfers (settlement_id, payer_id, payee_id, amount)
  select v_settlement_id, d.user_id, c.user_id,
    (least(d.range_end, c.range_end) - greatest(d.range_start, c.range_start))::numeric / 100
  from debtors d
  join creditors c on least(d.range_end, c.range_end) > greatest(d.range_start, c.range_start);

  if not exists (select 1 from public.settlement_transfers t where t.settlement_id = v_settlement_id) then
    update public.settlements set status = 'completed', completed_at = now() where id = v_settlement_id;
  end if;

  return v_settlement_id;
end;
$$;

create or replace function public.mark_settlement_transfer_paid(p_transfer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settlement_id uuid;
begin
  update public.settlement_transfers t
  set status = 'paid', paid_at = now()
  from public.settlements s
  where t.id = p_transfer_id
    and t.settlement_id = s.id
    and t.payer_id = auth.uid()
    and t.status = 'pending'
    and s.status = 'active'
  returning t.settlement_id into v_settlement_id;
  if v_settlement_id is null then
    raise exception '只有此筆款項的付款人可標記匯款，且結算必須仍在進行中。';
  end if;
  return v_settlement_id;
end;
$$;

create or replace function public.confirm_settlement_transfer_received(p_transfer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settlement_id uuid;
begin
  update public.settlement_transfers t
  set status = 'confirmed', confirmed_at = now()
  from public.settlements s
  where t.id = p_transfer_id
    and t.settlement_id = s.id
    and t.payee_id = auth.uid()
    and t.status = 'paid'
    and s.status = 'active'
  returning t.settlement_id into v_settlement_id;
  if v_settlement_id is null then
    raise exception '只有此筆款項的收款人可確認收款，且付款人需先標記已匯款。';
  end if;

  if not exists (
    select 1 from public.settlement_transfers t
    where t.settlement_id = v_settlement_id and t.status <> 'confirmed'
  ) then
    update public.settlements
    set status = 'completed', completed_at = now()
    where id = v_settlement_id and status = 'active';
  end if;
  return v_settlement_id;
end;
$$;

revoke all on function public.start_ledger_settlement(uuid) from public, anon;
revoke all on function public.mark_settlement_transfer_paid(uuid) from public, anon;
revoke all on function public.confirm_settlement_transfer_received(uuid) from public, anon;
grant execute on function public.start_ledger_settlement(uuid) to authenticated;
grant execute on function public.mark_settlement_transfer_paid(uuid) to authenticated;
grant execute on function public.confirm_settlement_transfer_received(uuid) to authenticated;

-- Once captured in a settlement, expense rows remain immutable for audit history.
create or replace function public.expense_is_unsettled(p_expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.expenses e
    where e.id = p_expense_id
      and public.is_ledger_member(e.ledger_id, auth.uid())
      and not exists (
        select 1 from public.settlement_expenses se where se.expense_id = e.id
      )
  );
$$;
revoke all on function public.expense_is_unsettled(uuid) from public, anon;
grant execute on function public.expense_is_unsettled(uuid) to authenticated;

create or replace function public.prevent_settled_expense_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.settlement_expenses se where se.expense_id = old.id
  ) then
    raise exception '此費用已進入結算或歷史紀錄，為保留帳目請新增調整費用，不可編輯或刪除。';
  end if;
  return old;
end;
$$;

drop trigger if exists prevent_settled_expense_mutation on public.expenses;
create trigger prevent_settled_expense_mutation
  before update or delete on public.expenses
  for each row execute procedure public.prevent_settled_expense_mutation();

drop policy if exists "Creators can delete expenses" on public.expenses;
create policy "Creators can delete expenses"
  on public.expenses for delete to authenticated
  using (
    created_by = auth.uid()
    and public.is_ledger_member(ledger_id, auth.uid())
    and public.expense_is_unsettled(id)
  );

notify pgrst, 'reload schema';
