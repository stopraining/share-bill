-- Run in Supabase Dashboard → SQL Editor.
-- Fixes silent no-op updates on expenses while preserving settled-expense protection.
-- A BEFORE UPDATE trigger must return NEW to allow the edited row to be stored.
create or replace function public.prevent_settled_expense_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Deleting a whole ledger cascades through its expense history.
  if tg_op = 'DELETE' and not exists (
    select 1 from public.ledgers l where l.id = old.ledger_id
  ) then
    return old;
  end if;

  if exists (
    select 1 from public.settlement_expenses se where se.expense_id = old.id
  ) then
    raise exception '此費用已進入結算或歷史紀錄，為保留帳目不可單獨編輯或刪除。';
  end if;

  if tg_op = 'UPDATE' then
    return new;
  end if;
  return old;
end;
$$;
