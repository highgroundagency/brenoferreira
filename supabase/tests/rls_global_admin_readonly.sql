-- pgTAP: global_admin lê todas as unidades e só escreve em units/cities/neighborhoods/profiles/catálogos globais
begin;
select plan(8);
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
select public.register_person(pg_temp.payload((select c1 from ids), 'Lucas', '41987650031'));
select pg_temp.logout();
select pg_temp.login('55555555-5555-4555-8555-555555555555', 'global_admin@test');
select ok((select count(*) from public.people) >= 1, 'global_admin lê people');
select is((select count(*)::int from public.units), 2, 'global_admin lê as duas unidades');
select throws_ok($$ update public.people set observation = 'x' $$, '42501', null, 'global_admin não escreve em people');
select throws_ok($$ insert into public.referrals (unit_id, person_id, team_id, referral_type) select p.unit_id, p.id, t.id, 'other' from public.people p, public.teams t where t.unit_id = p.unit_id and t.kind = 'central' limit 1 $$, '42501', null, 'global_admin não escreve em referrals');
select lives_ok($$ insert into public.cities (name, state, ibge_code) values ('Colombo', 'PR', '4105805') $$, 'global_admin escreve em cities');
select lives_ok($$ insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type) values (null, 'teste global', 99, '{"always": true}', 'central', 'other') $$, 'global_admin escreve catálogo global');
select throws_ok($$ insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type) values ((select id from public.units where slug = 'curitiba'), 'teste local', 99, '{"always": true}', 'central', 'other') $$, '42501', null, 'global_admin não escreve catálogo de unidade');
select lives_ok($$ select public.open_person_record((select id from public.people limit 1)) $$, 'global_admin abre ficha (auditado)');
select pg_temp.logout();
select * from finish();
rollback;
