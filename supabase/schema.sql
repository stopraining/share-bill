-- Run this in the Supabase Dashboard SQL Editor.
-- This schema stores one public profile row for each Supabase Auth user.
create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique not null,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

alter table public.users enable row level security;

drop policy if exists "Users can read their own profile" on public.users;
create policy "Users can read their own profile"
  on public.users for select
  to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.users;
create policy "Users can update their own profile"
  on public.users for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

-- One user may own or join any number of shared ledgers.
create table if not exists public.ledgers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  description text not null default '',
  currency text not null default 'TWD' check (currency ~ '^[A-Z]{3}$'),
  owner_id uuid not null references public.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ledger_members (
  ledger_id uuid not null references public.ledgers (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (ledger_id, user_id)
);

create index if not exists ledger_members_user_id_idx on public.ledger_members (user_id);

create table if not exists public.ledger_invitations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ledgers (id) on delete cascade,
  email text not null,
  invited_by uuid not null references public.users (id) on delete restrict,
  invitation_token uuid not null unique default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (email = lower(email))
);

create index if not exists ledger_invitations_ledger_id_idx on public.ledger_invitations (ledger_id);
create index if not exists ledger_invitations_email_idx on public.ledger_invitations (email);

create or replace function public.is_ledger_member(p_ledger_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.ledger_members lm
    where lm.ledger_id = p_ledger_id
      and lm.user_id = auth.uid()
      and p_user_id = auth.uid()
  );
$$;

create or replace function public.is_ledger_admin(p_ledger_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.ledger_members lm
    where lm.ledger_id = p_ledger_id
      and lm.user_id = auth.uid()
      and p_user_id = auth.uid()
      and lm.role in ('owner', 'admin')
  );
$$;

create or replace function public.add_ledger_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_members (ledger_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

drop trigger if exists on_ledger_created on public.ledgers;
create trigger on_ledger_created
  after insert on public.ledgers
  for each row execute procedure public.add_ledger_owner();

-- Create the ledger using the authenticated identity on the database side.
-- This avoids trusting a client-supplied owner_id and ensures the owner membership trigger runs.
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
  values (trim(p_name), trim(coalesce(p_description, '')), upper(coalesce(p_currency, 'TWD')), v_user_id)
  returning id into v_ledger_id;

  return v_ledger_id;
end;
$$;

create or replace function public.create_ledger_invitation(p_ledger_id uuid, p_email text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token uuid;
  v_email text := lower(trim(p_email));
begin
  if auth.uid() is null then
    raise exception '請先登入後再邀請成員。';
  end if;
  if not public.is_ledger_admin(p_ledger_id, auth.uid()) then
    raise exception '只有帳本擁有者或管理員可以邀請成員。';
  end if;
  if v_email = '' or position('@' in v_email) < 2 then
    raise exception '請輸入有效的電子郵件地址。';
  end if;
  if exists (
    select 1 from public.ledger_members lm
    join public.users u on u.id = lm.user_id
    where lm.ledger_id = p_ledger_id and lower(u.email) = v_email
  ) then
    raise exception '此使用者已經是帳本成員。';
  end if;

  insert into public.ledger_invitations (ledger_id, email, invited_by)
  values (p_ledger_id, v_email, auth.uid())
  returning invitation_token into v_token;
  return v_token;
end;
$$;

create or replace function public.accept_ledger_invitation(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation public.ledger_invitations%rowtype;
  v_email text;
begin
  if auth.uid() is null then
    raise exception '請先登入後再接受邀請。';
  end if;
  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();

  select * into v_invitation
  from public.ledger_invitations i
  where i.invitation_token = p_token
  for update;

  if not found or v_invitation.status <> 'pending' then
    raise exception '邀請連結無效或已被使用。';
  end if;
  if v_invitation.expires_at <= now() then
    update public.ledger_invitations set status = 'expired' where id = v_invitation.id;
    raise exception '邀請已過期，請請帳本管理員重新邀請。';
  end if;
  if v_invitation.email <> v_email then
    raise exception '此邀請寄給其他電子郵件，請使用受邀的帳號登入。';
  end if;

  insert into public.ledger_members (ledger_id, user_id, role)
  values (v_invitation.ledger_id, auth.uid(), 'member')
  on conflict (ledger_id, user_id) do nothing;

  update public.ledger_invitations
  set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  where id = v_invitation.id;
  return v_invitation.ledger_id;
end;
$$;

alter table public.ledgers enable row level security;
alter table public.ledger_members enable row level security;
alter table public.ledger_invitations enable row level security;

drop policy if exists "Members can read their ledgers" on public.ledgers;
create policy "Members can read their ledgers"
  on public.ledgers for select to authenticated
  using (public.is_ledger_member(id, auth.uid()));

drop policy if exists "Authenticated users can create ledgers" on public.ledgers;
create policy "Authenticated users can create ledgers"
  on public.ledgers for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "Owners can update their ledgers" on public.ledgers;
create policy "Owners can update their ledgers"
  on public.ledgers for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "Owners can delete their ledgers" on public.ledgers;
create policy "Owners can delete their ledgers"
  on public.ledgers for delete to authenticated
  using (owner_id = auth.uid());

drop policy if exists "Members can read ledger membership" on public.ledger_members;
create policy "Members can read ledger membership"
  on public.ledger_members for select to authenticated
  using (user_id = auth.uid() or public.is_ledger_member(ledger_id, auth.uid()));

-- Invitation rows are intentionally accessible through the two RPC functions only.
revoke all on public.ledger_invitations from anon, authenticated;
revoke all on function public.is_ledger_member(uuid, uuid) from public, anon;
revoke all on function public.is_ledger_admin(uuid, uuid) from public, anon;
grant execute on function public.is_ledger_member(uuid, uuid) to authenticated;
grant execute on function public.is_ledger_admin(uuid, uuid) to authenticated;
revoke all on function public.create_ledger_invitation(uuid, text) from public, anon;
revoke all on function public.accept_ledger_invitation(uuid) from public, anon;
revoke all on function public.create_ledger(text, text, text) from public, anon;
grant execute on function public.create_ledger_invitation(uuid, text) to authenticated;
grant execute on function public.accept_ledger_invitation(uuid) to authenticated;
grant execute on function public.create_ledger(text, text, text) to authenticated;

-- Expense schema is ledger-scoped so separate groups never share bill records.
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

-- Safe upgrade for projects where expenses was created by an earlier schema version.
alter table public.expenses
  add column if not exists payer_name text not null default '';

create index if not exists expenses_ledger_date_idx on public.expenses (ledger_id, expense_date desc);

create table if not exists public.expense_splits (
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete restrict,
  amount numeric(12, 2) not null check (amount >= 0),
  primary key (expense_id, user_id)
);

create or replace function public.is_expense_ledger_member(p_expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.expenses e
    where e.id = p_expense_id and public.is_ledger_member(e.ledger_id, auth.uid())
  );
$$;

alter table public.expenses enable row level security;
alter table public.expense_splits enable row level security;

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

revoke all on function public.is_expense_ledger_member(uuid) from public, anon;
grant execute on function public.is_expense_ledger_member(uuid) to authenticated;

grant select, insert, update, delete on public.ledgers to authenticated;
grant select on public.ledger_members to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
grant select, insert, update, delete on public.expense_splits to authenticated;

-- Refresh PostgREST's function cache so supabase.rpc() sees create_ledger immediately.
notify pgrst, 'reload schema';
