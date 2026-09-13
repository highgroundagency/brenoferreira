-- pgTAP: evangelista não lê a base; só o que cadastrou via get_my_registrations; perde telefone após 30 dias; sem transições
begin;
select plan(10);
create or replace function pg_temp.login(p_user uuid, p_email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'email', p_email, 'user_metadata', json_build_object('full_name', 'Novo Usuário'))::text, true);
  execute 'grant select on all tables in schema ' || pg_my_temp_schema()::regnamespace || ' to authenticated';
  perform set_config('role', 'authenticated', true);
end $$;
create or replace function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
create or replace function pg_temp.payload(p_client uuid, p_name text, p_phone text, p_owner text default 'self', p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'client_uuid', p_client, 'full_name', p_name, 'phone', p_phone, 'phone_owner', p_owner, 'is_adult', true,
    'neighborhood_id', (select id from public.neighborhoods where normalized_name = 'xaxim'),
    'address_kind', 'fixed', 'street', 'Rua das Flores', 'number', '123', 'postal_code', '81810-000',
    'needs', '[{"need_type":"food"},{"need_type":"furniture","item_code":"cama"}]'::jsonb,
    'children', '["15_17","15_17","12_14"]'::jsonb,
    'consent', '{"accepted":true,"version":"v1"}'::jsonb,
    'needs_job', true, 'occupation_area', 'cozinha', 'observation', 'chegou sozinho') || p_extra
$$;
create temp table ids as select gen_random_uuid() as c1;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select lives_ok($$ select public.register_person(pg_temp.payload((select c1 from ids), 'Ana Souza', '41987650011')) $$, 'evangelista cadastra');
select is((select count(*)::int from public.people), 0, 'evangelista não lê people (RLS)');
select is((select count(*)::int from public.people_contacts), 0, 'evangelista não lê people_contacts');
select is((select count(*)::int from public.get_my_registrations()), 1, 'vê o próprio cadastro');
select ok((select (r->>'phone_e164') is not null from public.get_my_registrations() r), 'telefone visível nos primeiros 30 dias');
select is((select count(*)::int from public.app_settings where key = 'consent_text_v1'), 1, 'lê o texto de consentimento público');
select is((select count(*)::int from public.app_settings where key = 'edge_base_url'), 0, 'não lê configurações privadas');
select is((select count(*)::int from public.get_team_queue('basic_food')), 0, 'não vê filas');
select pg_temp.logout();
create temp table ref as select id from public.referrals limit 1;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select throws_ok($$ select public.referral_transition((select id from ref), 'triaged') $$, '42501', null, 'não transiciona encaminhamentos');
select pg_temp.logout();
update public.people set created_at = now() - interval '31 days' where client_uuid = (select c1 from ids);
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select ok((select (r->>'phone_e164') is null from public.get_my_registrations() r), 'telefone some após 30 dias');
select pg_temp.logout();
select * from finish();
rollback;
