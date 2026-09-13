-- Shim para validar migrations em um Postgres "puro" (sem Docker/Supabase CLI).
-- Emula o mínimo dos schemas auth, vault, cron e net e os roles do Supabase. NUNCA aplicar em produção.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then create role supabase_auth_admin nologin; end if;
end $$;

create schema if not exists extensions;
create schema if not exists auth;
create table if not exists auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text unique, encrypted_password text,
  email_confirmed_at timestamptz, invited_at timestamptz, confirmation_token text, confirmation_sent_at timestamptz,
  recovery_token text, recovery_sent_at timestamptz, email_change_token_new text, email_change text, email_change_sent_at timestamptz,
  last_sign_in_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb, is_super_admin boolean,
  created_at timestamptz, updated_at timestamptz, phone text, phone_confirmed_at timestamptz, phone_change text default '',
  phone_change_token text default '', phone_change_sent_at timestamptz, email_change_token_current text default '',
  email_change_confirm_status smallint default 0, banned_until timestamptz, reauthentication_token text default '',
  reauthentication_sent_at timestamptz, is_sso_user boolean default false, deleted_at timestamptz, is_anonymous boolean default false
);
create table if not exists auth.identities (
  id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade, provider_id text,
  identity_data jsonb, provider text, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz, email text
);
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create or replace function auth.role() returns text language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt(), auth.role() to anon, authenticated, service_role;

create schema if not exists vault;
create table if not exists vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text, description text, created_at timestamptz default now());
create or replace view vault.decrypted_secrets as select id, name, secret, secret as decrypted_secret, description, created_at from vault.secrets;
create or replace function vault.create_secret(new_secret text, new_name text default null, new_description text default null) returns uuid
language sql as $$ insert into vault.secrets (name, secret, description) values (new_name, new_secret, new_description) returning id $$;

-- cron/net: stubs só quando as extensões reais não existem
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    create schema if not exists cron;
    create table if not exists cron.job (jobid bigserial primary key, jobname text unique, schedule text, command text);
    create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as
      $f$ insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
          on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
  end if;
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    create schema if not exists net;
    create or replace function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb, headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000) returns bigint
      language sql as $f$ select 1::bigint $f$;
  end if;
end $$;

-- Como no Supabase: roles de API enxergam public e extensions
grant usage on schema public, extensions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
