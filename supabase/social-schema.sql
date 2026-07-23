-- =====================================================================
--  Joint Space — social layer: profiles, connections, direct messages
--  Run this once in Supabase → SQL Editor → New query → Run.
--  Safe to re-run (uses IF NOT EXISTS / DROP POLICY guards).
-- =====================================================================

-- ---------- 1) PROFILES : a public identity + @handle per user ----------
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text,
  display_name text,
  color        text default '#159d58',
  created_at   timestamptz default now()
);

-- case-insensitive unique @handle
create unique index if not exists profiles_username_lower_idx
  on public.profiles (lower(username));

alter table public.profiles enable row level security;

drop policy if exists profiles_read   on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;

-- any signed-in user can read profiles (needed to search @handles)
create policy profiles_read on public.profiles
  for select to authenticated using (true);
-- you may only create / edit your own profile row
create policy profiles_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- auto-create a blank profile the moment someone signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, color)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
          '#159d58')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- backfill profiles for any users who signed up before this ran
insert into public.profiles (id, display_name, color)
select u.id,
       coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
       '#159d58'
from auth.users u
on conflict (id) do nothing;

-- ---------- 2) CONNECTIONS : friend / colleague requests ----------
create table if not exists public.connections (
  id         uuid primary key default gen_random_uuid(),
  requester  uuid not null references auth.users(id) on delete cascade,
  addressee  uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz default now(),
  unique (requester, addressee)
);

alter table public.connections enable row level security;

drop policy if exists conn_read   on public.connections;
drop policy if exists conn_insert on public.connections;
drop policy if exists conn_update on public.connections;
drop policy if exists conn_delete on public.connections;

-- see rows where you are either side
create policy conn_read on public.connections
  for select to authenticated
  using (requester = auth.uid() or addressee = auth.uid());
-- send a request as yourself (not to yourself)
create policy conn_insert on public.connections
  for insert to authenticated
  with check (requester = auth.uid() and addressee <> auth.uid());
-- only the addressee can accept (pending -> accepted)
create policy conn_update on public.connections
  for update to authenticated
  using (addressee = auth.uid()) with check (addressee = auth.uid());
-- either side can remove / decline
create policy conn_delete on public.connections
  for delete to authenticated
  using (requester = auth.uid() or addressee = auth.uid());

-- helper: are two users accepted-connected?
create or replace function public.are_connected(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.connections
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

-- ---------- 3) DIRECT MESSAGES ----------
create table if not exists public.direct_messages (
  id         uuid primary key default gen_random_uuid(),
  sender     uuid not null references auth.users(id) on delete cascade,
  recipient  uuid not null references auth.users(id) on delete cascade,
  body       text not null,
  created_at timestamptz default now()
);
create index if not exists dm_pair_idx
  on public.direct_messages (sender, recipient, created_at);

alter table public.direct_messages enable row level security;

drop policy if exists dm_read   on public.direct_messages;
drop policy if exists dm_insert on public.direct_messages;

-- read messages you sent or received
create policy dm_read on public.direct_messages
  for select to authenticated
  using (sender = auth.uid() or recipient = auth.uid());
-- send only as yourself, and only to an accepted connection
create policy dm_insert on public.direct_messages
  for insert to authenticated
  with check (sender = auth.uid() and public.are_connected(auth.uid(), recipient));

-- ---------- 4) REALTIME : stream new DMs + connection changes ----------
do $$ begin
  alter publication supabase_realtime add table public.direct_messages;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.connections;
exception when duplicate_object then null; end $$;

-- Done. Tables: profiles, connections, direct_messages (all RLS-protected).

-- =====================================================================
--  5) CONNECTION LABELS : per-user, per-space category for each contact
--     (so the same person can be a Work "Colleague" AND a Casual "Friend")
-- =====================================================================
create table if not exists public.connection_meta (
  owner      uuid not null references auth.users(id) on delete cascade,
  other      uuid not null references auth.users(id) on delete cascade,
  space      text not null check (space in ('work','casual')),
  label      text,          -- work: Colleague/Manager/Report/Teammate · casual: Friend/Family/Partner
  team       text,          -- work only: team name (yours or another)
  created_at timestamptz default now(),
  primary key (owner, other, space)
);
alter table public.connection_meta enable row level security;
drop policy if exists cmeta_all on public.connection_meta;
create policy cmeta_all on public.connection_meta
  for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
