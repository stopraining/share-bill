-- Run in Supabase Dashboard → SQL Editor to enable ledger renaming.
-- Only the ledger owner may rename a ledger; the name must be 1–80 characters.
create or replace function public.rename_ledger(p_ledger_id uuid, p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception '請先登入後修改帳本名稱。';
  end if;
  if char_length(trim(coalesce(p_name, ''))) not between 1 and 80 then
    raise exception '帳本名稱需為 1 到 80 個字。';
  end if;

  update public.ledgers
  set name = trim(p_name), updated_at = now()
  where id = p_ledger_id and owner_id = auth.uid();

  if not found then
    raise exception '找不到帳本，或只有帳本擁有者可以修改名稱。';
  end if;
  return p_ledger_id;
end;
$$;

revoke all on function public.rename_ledger(uuid, text) from public, anon;
grant execute on function public.rename_ledger(uuid, text) to authenticated;
notify pgrst, 'reload schema';