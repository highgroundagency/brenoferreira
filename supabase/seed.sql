-- Seed LOCAL (supabase start / validação local). Não usar em produção: ver supabase/seeds/prod.sql.
-- Senha de todos os usuários de teste: Teste123!
set search_path = public, extensions;

-- Unidade de teste para provar isolamento (isolation_second_unit.sql)
insert into public.units (slug, name) values ('teste', 'Unidade de Teste') on conflict (slug) do nothing;
insert into public.unit_neighborhoods (unit_id, neighborhood_id)
select u.id, n.id from public.units u, public.neighborhoods n join public.cities c on c.id = n.city_id
where u.slug = 'teste' and c.ibge_code = '4106902' and n.normalized_name in ('centro', 'xaxim')
on conflict do nothing;
insert into public.teams (unit_id, kind, name, active)
select u.id, 'central', 'Central (teste)', true from public.units u where u.slug = 'teste' on conflict do nothing;
insert into public.app_settings (unit_id, key, value, is_public)
select u.id, 'consent_text_v1', (select value from public.app_settings a join public.units c on c.id = a.unit_id where c.slug = 'curitiba' and a.key = 'consent_text_v1'), true
from public.units u where u.slug = 'teste' on conflict do nothing;

-- URL das Edge Functions vista de dentro do Postgres local (docker: supabase_kong_<project>; puro: localhost)
insert into public.app_settings (unit_id, key, value, is_public)
select u.id, 'edge_base_url', to_jsonb('http://host.docker.internal:54321/functions/v1'::text), false
from public.units u where u.slug in ('curitiba', 'teste') on conflict (unit_id, key) do nothing;

-- Segredo compartilhado das Edge Functions (dev). Em produção é criado pelo CI a partir de EDGE_SHARED_SECRET.
select vault.create_secret('dev-edge-secret', 'edge_shared_secret', 'bearer das Edge Functions (dev)')
where not exists (select 1 from vault.secrets where name = 'edge_shared_secret');

-- Usuários de teste (auth.users + identities) e perfis
do $$
declare
  u record;
  v_unit uuid;
  v_id uuid;
  v_team uuid;
begin
  for u in select * from (values
      ('11111111-1111-4111-8111-111111111111'::uuid, 'evangelist@test', 'Eva Evangelista', 'evangelist', 'curitiba', null),
      ('22222222-2222-4222-8222-222222222222'::uuid, 'central@test', 'Carla Central', 'central', 'curitiba', 'central'),
      ('33333333-3333-4333-8333-333333333333'::uuid, 'basic_food@test', 'Beto Cesta', 'team_member', 'curitiba', 'basic_food'),
      ('44444444-4444-4444-8444-444444444444'::uuid, 'unit_admin@test', 'Ana Admin', 'unit_admin', 'curitiba', null),
      ('55555555-5555-4555-8555-555555555555'::uuid, 'global_admin@test', 'Gabriel Global', 'global_admin', null, null),
      ('66666666-6666-4666-8666-666666666666'::uuid, 'central_teste@test', 'Tereza Teste', 'central', 'teste', 'central')
    ) as t(id, email, full_name, role, unit_slug, team_kind)
  loop
    select id into v_unit from public.units where slug = u.unit_slug;
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
            extensions.crypt('Teste123!', extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', '')
    on conflict (id) do nothing;
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub', u.id::text, 'email', u.email), 'email', now(), now(), now())
    on conflict do nothing;
    insert into public.profiles (id, unit_id, full_name, role, active, volunteer_terms_version, volunteer_terms_accepted_at)
    values (u.id, v_unit, u.full_name, u.role, true, 'v1', now())
    on conflict (id) do nothing;
    if u.team_kind is not null then
      select id into v_team from public.teams where unit_id = v_unit and kind = u.team_kind;
      insert into public.team_members (unit_id, team_id, profile_id, member_role)
      values (v_unit, v_team, u.id, 'member') on conflict do nothing;
    end if;
  end loop;
end $$;
