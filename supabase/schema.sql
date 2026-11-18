-- Nizam: database setup for Supabase
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run more than once.

-- 1) Profiles: one row per user (answers from the welcome questions)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  first_name  text,
  last_name   text,
  email       text,
  gender      text check (gender in ('m','f','n')),
  birth_date  date,
  country     text,
  occupation  text,
  purposes    int[] not null default '{}',
  lang        text,
  daily_goal  int,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

-- 2) Entries: every tracked session
create table if not exists public.entries (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sphere      smallint not null check (sphere between 0 and 4),
  seconds     int not null check (seconds >= 0),
  ended_at    bigint not null,            -- milliseconds since 1970
  activity    text,
  deleted     boolean not null default false,
  updated_at  timestamptz not null default clock_timestamp()
);
create index if not exists entries_user_updated on public.entries (user_id, updated_at);

-- 3) Settings: goal, language, hidden spheres
create table if not exists public.user_settings (
  user_id     uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data        jsonb not null default '{}',
  updated_at  timestamptz not null default clock_timestamp()
);

-- 4) Admins: who may see the statistics page
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- updated_at is always set by the server
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := clock_timestamp(); return new; end $$;

drop trigger if exists entries_touch on public.entries;
create trigger entries_touch before insert or update on public.entries
  for each row execute function public.touch_updated_at();
drop trigger if exists settings_touch on public.user_settings;
create trigger settings_touch before insert or update on public.user_settings
  for each row execute function public.touch_updated_at();

-- Row Level Security: everyone sees and changes only their own rows
alter table public.profiles      enable row level security;
alter table public.entries       enable row level security;
alter table public.user_settings enable row level security;
alter table public.admins        enable row level security;

drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile insert" on public.profiles;
drop policy if exists "own profile update" on public.profiles;
create policy "own profile read"   on public.profiles for select to authenticated using (id = auth.uid());
create policy "own profile insert" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "own entries read"   on public.entries;
drop policy if exists "own entries insert" on public.entries;
drop policy if exists "own entries update" on public.entries;
create policy "own entries read"   on public.entries for select to authenticated using (user_id = auth.uid());
create policy "own entries insert" on public.entries for insert to authenticated with check (user_id = auth.uid());
create policy "own entries update" on public.entries for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own settings read"   on public.user_settings;
drop policy if exists "own settings insert" on public.user_settings;
drop policy if exists "own settings update" on public.user_settings;
create policy "own settings read"   on public.user_settings for select to authenticated using (user_id = auth.uid());
create policy "own settings insert" on public.user_settings for insert to authenticated with check (user_id = auth.uid());
create policy "own settings update" on public.user_settings for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- admins: no policies → nobody can read or change it from the app

-- Table access for signed-in users only (anonymous visitors get nothing)
revoke all on public.profiles, public.entries, public.user_settings, public.admins from anon, authenticated;
grant select, insert, update on public.profiles, public.entries, public.user_settings to authenticated;

-- Is the current user an admin?
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

-- Statistics for the admin page (only admins can call it)
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not exists (select 1 from public.admins where user_id = auth.uid()) then
    raise exception 'not allowed';
  end if;
  select jsonb_build_object(
    'users',      (select count(*) from profiles),
    'new_today',  (select count(*) from profiles where created_at >= date_trunc('day', now())),
    'new_7d',     (select count(*) from profiles where created_at > now() - interval '7 days'),
    'new_30d',    (select count(*) from profiles where created_at > now() - interval '30 days'),
    'active_1d',  (select count(*) from profiles where last_seen > now() - interval '1 day'),
    'active_7d',  (select count(*) from profiles where last_seen > now() - interval '7 days'),
    'active_30d', (select count(*) from profiles where last_seen > now() - interval '30 days'),
    'avg_age',    (select round(avg(extract(year from age(birth_date)))::numeric, 1) from profiles where birth_date is not null),
    'hours',      (select round(coalesce(sum(seconds),0) / 3600.0) from entries where not deleted),
    'sessions',   (select count(*) from entries where not deleted),
    'countries',  (select coalesce(jsonb_agg(jsonb_build_object('k', country, 'n', n) order by n desc), '[]') from
                    (select country, count(*) n from profiles where country is not null group by country) x),
    'gender',     (select coalesce(jsonb_agg(jsonb_build_object('k', gender, 'n', n) order by n desc), '[]') from
                    (select gender, count(*) n from profiles where gender is not null group by gender) x),
    'occupation', (select coalesce(jsonb_agg(jsonb_build_object('k', occupation, 'n', n) order by n desc), '[]') from
                    (select occupation, count(*) n from profiles where occupation is not null group by occupation) x),
    'purposes',   (select coalesce(jsonb_agg(jsonb_build_object('k', p, 'n', n) order by n desc), '[]') from
                    (select unnest(purposes) p, count(*) n from profiles group by 1) x),
    'langs',      (select coalesce(jsonb_agg(jsonb_build_object('k', lang, 'n', n) order by n desc), '[]') from
                    (select lang, count(*) n from profiles where lang is not null group by lang) x),
    'ages',       (select coalesce(jsonb_agg(jsonb_build_object('k', g, 'n', n) order by g), '[]') from
                    (select case when a < 18 then '13–17' when a < 25 then '18–24' when a < 35 then '25–34'
                                 when a < 45 then '35–44' when a < 55 then '45–54' else '55+' end g, count(*) n
                       from (select extract(year from age(birth_date))::int a from profiles where birth_date is not null) y
                      group by 1) x),
    'spheres',    (select coalesce(jsonb_agg(jsonb_build_object('k', sphere, 'n', round(h)) order by sphere), '[]') from
                    (select sphere, sum(seconds) / 3600.0 h from entries where not deleted group by sphere) x),
    'signups',    (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d), '[]') from
                    (select to_char(date_trunc('day', created_at), 'YYYY-MM-DD') d, count(*) n from profiles
                      where created_at > now() - interval '30 days' group by 1) x),
    'recent',     (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from
                    (select first_name, last_name, country, created_at, last_seen from profiles
                      order by created_at desc limit 50) x)
  ) into r;
  return r;
end $$;

-- Let a user delete their own account and all their data
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.is_admin(), public.admin_stats(), public.delete_my_account() from public, anon;
grant execute on function public.is_admin(), public.admin_stats(), public.delete_my_account() to authenticated;
