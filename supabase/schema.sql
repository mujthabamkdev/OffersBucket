-- OffersBucket cloud layer.
-- Device storage remains usable when these tables are not configured.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  brand text not null,
  title text not null,
  description text not null default '',
  original_message text not null default '',
  code text not null default '',
  category text not null,
  source text not null default 'Custom',
  valid_until timestamptz not null,
  saved_at timestamptz not null default now(),
  is_favorite boolean not null default false,
  is_archived boolean not null default false,
  color_value bigint not null default 4294929771,
  icon_key text not null default 'local_offer',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, client_id)
);

create index if not exists offers_user_active_idx
  on public.offers (user_id, is_archived, valid_until);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  expiring_soon boolean not null default true,
  favorite_updates boolean not null default true,
  best_deals boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.connected_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('google_drive', 'icloud', 'email')),
  status text not null default 'disconnected',
  scopes text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);

alter table public.profiles enable row level security;
alter table public.offers enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.connected_sources enable row level security;

create policy "profiles are private"
  on public.profiles for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "users manage own offers"
  on public.offers for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users manage own notification preferences"
  on public.notification_preferences for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "users manage own connected sources"
  on public.connected_sources for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  insert into public.notification_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
