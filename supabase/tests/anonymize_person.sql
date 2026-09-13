-- pgTAP: anonymize_person apaga PII de todas as tabelas e mantém bairro/estágio para métricas
begin;
select plan(9);
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
select public.register_person(pg_temp.payload((select c1 from ids), 'Rosa Oliveira', '41987650051'));
select pg_temp.logout();
create temp table t as select id as person_id, neighborhood_id from public.people where client_uuid = (select c1 from ids);
select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
select lives_ok($$ select public.anonymize_person((select person_id from t), 'request') $$, 'central anonimiza');
select pg_temp.logout();
select is((select count(*)::int from public.people_contacts where person_id = (select person_id from t)), 0, 'contato apagado');
select is((select count(*)::int from public.children where person_id = (select person_id from t)), 0, 'filhos apagados');
select is((select stage from public.people where id = (select person_id from t)), 'anonymized', 'estágio anonymized');
select is((select neighborhood_id from public.people where id = (select person_id from t)), (select neighborhood_id from t), 'bairro preservado para métricas');
select is((select count(*)::int from public.message_log where person_id = (select person_id from t) and (to_phone_e164 is not null or status = 'queued')), 0, 'mensagens sem telefone e não enfileiradas');
select is((select count(*)::int from public.person_events where person_id = (select person_id from t) and payload <> '{}'::jsonb and event_type <> 'anonymized'), 0, 'payloads da timeline limpos');
select is((select count(*)::int from public.notifications where ref_table = 'people' and ref_id = (select person_id from t) and title like '%Rosa%'), 0, 'notificações sem nome');
select is((select count(*)::int from public.referrals where person_id = (select person_id from t) and status not in ('done', 'cancelled')), 0, 'encaminhamentos abertos cancelados');
select * from finish();
rollback;
