-- Run this in Supabase Dashboard → SQL Editor if the app reports:
-- Could not find the function public.create_ledger(...) in the schema cache
--
-- This (re)creates the RPC with all three named parameters and refreshes PostgREST.
create or replace function public.create_ledger(
  p_name text,
  p_description text,
  p_currency text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ledger_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception '請先登入後再建立帳本。';
  end if;
  if not exists (select 1 from public.users u where u.id = v_user_id) then
    raise exception '找不到使用者個人資料，請重新登入或聯絡管理員。';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 80 then
    raise exception '帳本名稱需為 1 到 80 個字。';
  end if;

  insert into public.ledgers (name, description, currency, owner_id)
  values (
    trim(p_name),
    trim(coalesce(p_description, '')),
    upper(coalesce(p_currency, 'TWD')),
    v_user_id
  )
  returning id into v_ledger_id;

  return v_ledger_id;
end;
$$;

revoke all on function public.create_ledger(text, text, text) from public, anon;
grant execute on function public.create_ledger(text, text, text) to authenticated;
notify pgrst, 'reload schema';
