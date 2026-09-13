-- 001 — extensões, tenancy (units) e geografia de referência (global)
-- Convenções: enums como text + check; unit_id NOT NULL em toda tabela operacional; identificadores em inglês.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- pg_cron e pg_net existem no Supabase; em um Postgres "puro" (validação local) são ignorados.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end $$;

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Tenant: uma unidade = uma cidade/franquia do Transtornar
-- ---------------------------------------------------------------------------
create table public.units (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  country_code char(2) not null default 'BR',
  timezone text not null default 'America/Sao_Paulo',
  locale text not null default 'pt-BR',
  whatsapp_phone_number_id text,
  whatsapp_waba_id text,
  whatsapp_display_name text,
  whatsapp_token_secret_name text not null default 'WHATSAPP_ACCESS_TOKEN',
  settings jsonb not null default '{
    "quiet_hours": {"start": "21:00", "end": "08:00"},
    "first_contact_delay_minutes": 10,
    "first_contact_mode": "video_first",
    "central_hours": {"weekdays": "09:00-18:00"}
  }'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint units_first_contact_mode_chk check (settings->>'first_contact_mode' in ('video_first', 'optin_first'))
);
create trigger units_set_updated_at before update on public.units for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Referência geográfica global (IBGE/IPPUC): sem unit_id
-- ---------------------------------------------------------------------------
create table public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  state char(2) not null,
  country_code char(2) not null default 'BR',
  ibge_code text unique,
  unique (name, state, country_code)
);

create or replace function public.normalize_text(p text) returns text
language sql immutable strict as $$
  select regexp_replace(lower(extensions.unaccent(p)), '\s+', ' ', 'g')
$$;

create table public.neighborhoods (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.cities(id),
  name text not null,
  normalized_name text not null,
  aliases text[] not null default '{}',
  region text,
  unique (city_id, normalized_name)
);
create index neighborhoods_trgm_idx on public.neighborhoods using gin (normalized_name extensions.gin_trgm_ops);
create index neighborhoods_aliases_idx on public.neighborhoods using gin (aliases);

-- Cobertura de cada unidade (permite região metropolitana e mais de uma unidade por cidade)
create table public.unit_neighborhoods (
  unit_id uuid not null references public.units(id) on delete cascade,
  neighborhood_id uuid not null references public.neighborhoods(id),
  primary key (unit_id, neighborhood_id)
);

-- Chave/valor por unidade. is_public = legível por qualquer papel da unidade (ex.: texto de consentimento);
-- o restante (ex.: edge_base_url) só por funções security definer.
create table public.app_settings (
  unit_id uuid not null references public.units(id) on delete cascade,
  key text not null,
  value jsonb not null,
  is_public boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (unit_id, key)
);
create trigger app_settings_set_updated_at before update on public.app_settings for each row execute function public.set_updated_at();

-- Busca de bairro tolerante a grafia ("chaxim" -> Xaxim)
create or replace function public.find_neighborhood(p_city_id uuid, p_text text) returns uuid
language sql stable as $$
  select n.id from public.neighborhoods n
  where n.city_id = p_city_id
    and (n.normalized_name = public.normalize_text(p_text) or public.normalize_text(p_text) = any (n.aliases))
  union all
  select n.id from public.neighborhoods n
  where n.city_id = p_city_id
  order by 1
  limit 1
$$;
