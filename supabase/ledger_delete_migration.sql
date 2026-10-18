-- Run in Supabase Dashboard → SQL Editor to allow owners to delete a ledger
-- and all of its expenses and settlement history.
-- Existing settlement history remains protected from standalone expense edits/deletes.
-- During a ledger cascade, the parent ledger is already gone when the expense
-- delete trigger runs; allow that cascade to remove the complete ledger history.
alter table public.settlement_expenses
  drop constraint if exists settlement_expenses_expense_id_fkey;

alter table public.settlement_expenses
  add constraint settlement_expenses_expense_id_fkey
  foreign key (expense_id)
  references public.expenses (id)
  on delete cascade;

create or replace function public.prevent_settled_expense_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and not exists (
    select 1 from public.ledgers l where l.id = old.ledger_id
  ) then
    return old;
  end if;

  if exists (
    select 1 from public.settlement_expenses se where se.expense_id = old.id
  ) then
    raise exception '此費用已進入結算，為保留帳目不可單獨編輯或刪除。';
  end if;
  if tg_op = 'UPDATE' then
    return new;
  end if;

  return old;
end;
$$;

notify pgrst, 'reload schema';
