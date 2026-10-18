-- Run in Supabase Dashboard → SQL Editor to inspect the deployed expense edit RPC
-- and any database triggers that could change expenses.paid_by.

-- There should be one update_ledger_expense overload, with paid_by = p_paid_by
-- in the UPDATE statement.
select
  p.oid::regprocedure as function_signature,
  pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'update_ledger_expense';

-- Review all user-defined triggers on public.expenses.
select
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid) as trigger_definition,
  p.proname as trigger_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname = 'expenses'
  and not t.tgisinternal;
