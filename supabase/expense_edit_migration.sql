-- Run in Supabase Dashboard → SQL Editor to enable editing existing expenses.
-- Existing expense RLS policies already restrict direct deletes/updates to creators.
-- This RPC atomically updates the expense and replaces its split rows.
create or replace function public.update_ledger_expense(
  p_expense_id uuid,
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
  v_ledger_id uuid;
  v_updated_rows integer;
  v_saved_paid_by uuid;
  v_payer_name text;
  v_split_count integer;
  v_regular_share numeric(12, 2);
begin
  if v_user_id is null then
    raise exception '請先登入後再編輯費用。';
  end if;
  select e.ledger_id into v_ledger_id
  from public.expenses e
  where e.id = p_expense_id and e.created_by = v_user_id;
  if v_ledger_id is null then
    raise exception '找不到費用，或你不是此費用的建立者。';
  end if;
  if not public.is_ledger_member(v_ledger_id, v_user_id) then
    raise exception '你已不是此帳本的成員，無法編輯費用。';
  end if;
  if char_length(trim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception '費用名稱需為 1 到 120 個字。';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 9999999999.99 then
    raise exception '費用金額必須大於 0。';
  end if;
  if p_paid_by is null or not exists (
    select 1 from public.ledger_members lm
    where lm.ledger_id = v_ledger_id and lm.user_id = p_paid_by
  ) then
    raise exception '付款人必須是目前帳本的成員。';
  end if;
  if p_split_user_ids is null or cardinality(p_split_user_ids) = 0 then
    raise exception '請至少選擇一位分攤成員。';
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
    where requested.member_id is null
      or not exists (
        select 1 from public.ledger_members lm
        where lm.ledger_id = v_ledger_id and lm.user_id = requested.member_id
      )
  ) then
    raise exception '所有分攤者都必須是目前帳本的成員。';
  end if;

  select coalesce(nullif(trim(u.display_name), ''), u.email)
  into v_payer_name
  from public.users u
  where u.id = p_paid_by;

  update public.expenses
  set title = trim(p_title),
      amount = round(p_amount, 2),
      paid_by = p_paid_by,
      payer_name = coalesce(v_payer_name, ''),
      category = coalesce(nullif(trim(p_category), ''), '其他'),
      expense_date = coalesce(p_expense_date, current_date),
      notes = coalesce(p_notes, ''),
      updated_at = now()
  where id = p_expense_id and created_by = v_user_id;

  get diagnostics v_updated_rows = row_count;
  if v_updated_rows <> 1 then
    raise exception '費用資料沒有成功更新，請重新載入後再試。';
  end if;

  select e.paid_by into v_saved_paid_by
  from public.expenses e
  where e.id = p_expense_id;
  if v_saved_paid_by is distinct from p_paid_by then
    raise exception 'PAYER_UPDATE_MISMATCH: requested %, saved %. 請檢查 public.expenses 的 UPDATE trigger 或目前部署的 RPC。',
      p_paid_by, v_saved_paid_by;
  end if;

  delete from public.expense_splits where expense_id = p_expense_id;
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
    p_expense_id,
    ordered_members.member_id,
    case
      when ordered_members.row_number = ordered_members.member_count
        then round(p_amount, 2) - (v_regular_share * (ordered_members.member_count - 1))
      else v_regular_share
    end
  from ordered_members;

  return p_expense_id;
end;
$$;

revoke all on function public.update_ledger_expense(uuid, text, numeric, uuid, text, date, text, uuid[]) from public, anon;
grant execute on function public.update_ledger_expense(uuid, text, numeric, uuid, text, date, text, uuid[]) to authenticated;
notify pgrst, 'reload schema';
