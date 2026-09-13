-- pgTAP: isolamento entre unidades (curitiba x teste) e catálogo global x local
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
create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Curitibano', '41987650041'));
select pg_temp.logout();
select pg_temp.login('66666666-6666-4666-8666-666666666666', 'central_teste@test');
select is((select count(*)::int from public.people), 0, 'central da unidade teste não vê pessoas de curitiba');
select lives_ok($$ select public.register_person(pg_temp.payload((select c2 from ids), 'Testador', '41987650042')) $$, 'central da unidade teste cadastra na própria unidade');
select is((select count(*)::int from public.people), 1, 'vê só a própria pessoa');
select ok((select count(*) from public.routing_rules where unit_id is null) >= 5, 'vê as regras globais');
select pg_temp.logout();
insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type)
values ((select id from public.units where slug = 'curitiba'), 'regra só de curitiba', 1, '{"always": true}', 'central', 'other');
select pg_temp.login('66666666-6666-4666-8666-666666666666', 'central_teste@test');
select is((select count(*)::int from public.routing_rules where name = 'regra só de curitiba'), 0, 'não vê catálogo de outra unidade');
select is((select count(*)::int from public.v_conversions_by_neighborhood), 1, 'view agregada limitada à própria unidade');
select pg_temp.logout();
select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
select is((select count(*)::int from public.people where client_uuid = (select c2 from ids)), 0, 'central de curitiba não vê pessoa da unidade teste');
select is((select count(*)::int from public.routing_rules where name = 'regra só de curitiba'), 1, 'central de curitiba vê o catálogo local');
select pg_temp.logout();
select * from finish();
rollback;
