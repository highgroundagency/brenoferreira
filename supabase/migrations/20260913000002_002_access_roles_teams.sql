-- 002 — acesso, papéis e times
-- Papéis: evangelist | central | team_member | unit_admin | global_admin.
-- Sem Custom Access Token Hook: as funções auth_* leem profiles/team_members por auth.uid() a cada consulta
-- (dezenas de usuários; revogação imediata ao inativar o perfil).

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  unit_id uuid references public.units(id),            -- null apenas para global_admin
  full_name text not null,
  phone_e164 text,
  role text not null check (role in ('evangelist', 'central', 'team_member', 'unit_admin', 'global_admin')),
  active boolean not null default true,
  volunteer_terms_version text,
  volunteer_terms_accepted_at timestamptz,
  invited_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_unit_required_chk check (role = 'global_admin' or unit_id is not null)
);
create index profiles_unit_role_idx on public.profiles (unit_id, role) where active;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  email text not null,
  role text not null check (role in ('evangelist', 'central', 'team_member', 'unit_admin')),
  team_id uuid,                                          -- FK adicionada abaixo (teams)
  code text unique not null,
  invited_by uuid references public.profiles(id),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index invites_email_idx on public.invites (lower(email));

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  kind text not null check (kind in ('central', 'basic_food', 'home_items', 'education', 'employment', 'follow_up', 'logistics', 'strategy')),
  name text not null,
  notify_email text,
  active boolean not null default false,
  fallback_to_central boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, kind)
);
create trigger teams_set_updated_at before update on public.teams for each row execute function public.set_updated_at();
alter table public.invites add constraint invites_team_fk foreign key (team_id) references public.teams(id);

create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  team_id uuid not null references public.teams(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('member', 'lead')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (team_id, profile_id)
);
create index team_members_profile_idx on public.team_members (profile_id) where active;

-- ---------------------------------------------------------------------------
-- Funções de contexto de acesso (lidas pelas policies). Perfil inativo => null => policies falham.
-- ---------------------------------------------------------------------------
create or replace function public.auth_unit_id() returns uuid
language sql stable security definer set search_path = public as $$
  select p.unit_id from public.profiles p where p.id = auth.uid() and p.active
$$;

create or replace function public.auth_role() returns text
language sql stable security definer set search_path = public as $$
  select p.role from public.profiles p where p.id = auth.uid() and p.active
$$;

create or replace function public.auth_team_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(tm.team_id), '{}'::uuid[])
  from public.team_members tm
  join public.profiles p on p.id = tm.profile_id and p.active
  where tm.profile_id = auth.uid() and tm.active
$$;

create or replace function public.is_unit_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.auth_role() in ('central', 'unit_admin', 'global_admin')
$$;

-- Leitura: da própria unidade, ou global_admin (auditado nas RPCs de ficha)
create or replace function public.can_read_unit(p_unit_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin'
$$;

-- Escrita operacional: só papéis da própria unidade (global_admin nunca escreve em tabelas operacionais)
create or replace function public.can_write_unit(p_unit_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_unit_id = public.auth_unit_id() and public.auth_role() in ('central', 'unit_admin')
$$;

revoke execute on function public.auth_unit_id(), public.auth_role(), public.auth_team_ids(), public.is_unit_staff(),
  public.can_read_unit(uuid), public.can_write_unit(uuid) from public;
grant execute on function public.auth_unit_id(), public.auth_role(), public.auth_team_ids(), public.is_unit_staff(),
  public.can_read_unit(uuid), public.can_write_unit(uuid) to authenticated, service_role;
