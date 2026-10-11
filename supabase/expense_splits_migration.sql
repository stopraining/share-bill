-- Run in Supabase Dashboard → SQL Editor to support selecting the payer
-- and the members who split each new expense.
-- Requires the ledgers, ledger_members, users, expenses, and expense_splits tables.
create table if not exists public.expense_splits (
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete restrict,
  amount numeric(12, 2) not null check (amount >= 0),
  primary key (expense_id, user_id)
);

alter table public.expense_splits enable row level security;
grant select, insert, update, delete on public.expense_splits to authenticated;

drop policy if exists "Ledger members can read expense splits" on public.expense_splits;
create policy "Ledger members can read expense splits"
  on public.expense_splits for select to authenticated
  using (public.is_expense_ledger_member(expense_id));

drop policy if exists "Expense creators can manage splits" on public.expense_splits;
create policy "Expense creators can manage splits"
  on public.expense_splits for all to authenticated
  using (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and e.created_by = auth.uid()
        and public.is_ledger_member(e.ledger_id, auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.expenses e
      where e.id = expense_id and e.created_by = auth.uid()
        and public.is_ledger_member(e.ledger_id, auth.uid())
    )
  );

create or replace function public.create_ledger_expense(
  p_ledger_id uuid,
  p_title text,
  p_amount numeric,
  p_paid_by uuid,
  p_category text,
  p_expense_date date,
  p_notes text,
  p_split_user_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_expense_id uuid;
  v_payer_name text;
  v_split_count integer;
  v_regular_share numeric(12, 2);
begin
  if v_user_id is null then
    raise exception '請先登入後再新增支出。';
  end if;
  if not public.is_ledger_member(p_ledger_id, v_user_id) then
    raise exception '你不是此帳本的成員，無法新增支出。';
  end if;
  if char_length(trim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception '支出名稱需為 1 到 120 個字。';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 9999999999.99 then
    raise exception '支出金額必須大於 0。';
  end if;
  if p_paid_by is null or not exists (
    select 1 from public.ledger_members lm
    where lm.ledger_id = p_ledger_id and lm.user_id = p_paid_by
  ) then
    raise exception '付款人必須是目前帳本的成員。';
  end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) = 0 then
    raise exception '請至少選擇一位分攤成員。';
  end if;
  if exists (
    select 1 from unnest(p_split_user_ids) as requested(member_id)
    where requested.member_id is null
  ) then
    raise exception '分攤成員清單包含無效成員。';
  end if;

  select count(distinct requested.member_id)
  into v_split_count
  from unnest(p_split_user_ids) as requested(member_id);
  if v_split_count <> cardinality(p_split_user_ids) then
    raise exception '分攤成員不可重複選擇。';
  end if;
  if exists (
    select 1
    from unnest(p_split_user_ids) as requested(member_id)
    where not exists (
      select 1 from public.ledger_members lm
      where lm.ledger_id = p_ledger_id and lm.user_id = requested.member_id
    )
  ) then
    raise exception '所有分攤者都必須是目前帳本的成員。';
  end if;

  select coalesce(nullif(trim(u.display_name), ''), u.email)
  into v_payer_name
  from public.users u
  where u.id = p_paid_by;

  insert into public.expenses (
    ledger_id, title, amount, currency, paid_by, created_by,
    payer_name, category, expense_date, notes
  ) values (
    p_ledger_id, trim(p_title), round(p_amount, 2), 'TWD', p_paid_by, v_user_id,
    coalesce(v_payer_name, ''), coalesce(nullif(trim(p_category), ''), '其他'),
    coalesce(p_expense_date, current_date), coalesce(p_notes, '')
  ) returning id into v_expense_id;

  v_regular_share := trunc(round(p_amount, 2) / v_split_count, 2);
  with chosen_members as (
    select distinct requested.member_id
    from unnest(p_split_user_ids) as requested(member_id)
  ), ordered_members as (
    select
      chosen_members.member_id,
      row_number() over (order by chosen_members.member_id) as row_number,
      count(*) over () as member_count
    from chosen_members
  )
  insert into public.expense_splits (expense_id, user_id, amount)
  select
    v_expense_id,
    ordered_members.member_id,
    case
      when ordered_members.row_number = ordered_members.member_count
        then round(p_amount, 2) - (v_regular_share * (ordered_members.member_count - 1))
      else v_regular_share
    end
  from ordered_members;

  return v_expense_id;
end;
$$;

revoke all on function public.create_ledger_expense(uuid, text, numeric, uuid, text, date, text, uuid[]) from public, anon;
grant execute on function public.create_ledger_expense(uuid, text, numeric, uuid, text, date, text, uuid[]) to authenticated;
notify pgrst, 'reload schema';
