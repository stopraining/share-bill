-- Run in Supabase Dashboard → SQL Editor to enable listing all members
-- of the currently selected ledger without exposing users outside that ledger.
create or replace function public.list_ledger_members(p_ledger_id uuid)
returns table (
  user_id uuid,
  display_name text,
  email text,
  role text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception '請先登入後查看帳本成員。';
  end if;
  if not public.is_ledger_member(p_ledger_id, auth.uid()) then
    raise exception '只有帳本成員可以查看此帳本的成員。';
  end if;

  return query
  select lm.user_id, u.display_name, u.email, lm.role, lm.joined_at
  from public.ledger_members lm
  join public.users u on u.id = lm.user_id
  where lm.ledger_id = p_ledger_id
  order by case lm.role when 'owner' then 0 when 'admin' then 1 else 2 end, lm.joined_at;
end;
$$;

revoke all on function public.list_ledger_members(uuid) from public, anon;
grant execute on function public.list_ledger_members(uuid) to authenticated;
notify pgrst, 'reload schema';
