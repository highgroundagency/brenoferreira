-- pgTAP: mesclagem de duplicatas e acompanhamento (CRM)
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

create or replace function pg_temp.mark_sent(p_person uuid) returns void language sql as $$
  update public.message_log set status = 'sent', sent_at = now(), provider_message_id = 'wamid.' || gen_random_uuid()::text where person_id = p_person and status = 'queued'
$$;
create or replace function pg_temp.press(p_person uuid, p_button text) returns jsonb language sql as $$
  select public.handle_inbound((select unit_id from public.people where id = p_person),
    (select regexp_replace(phone_e164, '\D', '', 'g') from public.people_contacts where person_id = p_person),
    (select phone_e164 from public.people_contacts where person_id = p_person), 'button', jsonb_build_object('button_id', p_button, 'wamid', 'wamid.' || gen_random_uuid()::text))
$$;
create or replace function pg_temp.advance_now(p_person uuid) returns jsonb language sql as $$
  update public.person_journeys set next_send_at = now() - interval '1 minute' where person_id = p_person;
  select public.advance_journeys();
$$;

create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Original', '41987650101'));
select public.register_person(pg_temp.payload((select c2 from ids), 'Duplicata', '41987650101'));
select pg_temp.logout();
create temp table p as select (select id from public.people where client_uuid = (select c1 from ids)) as p1, (select id from public.people where client_uuid = (select c2 from ids)) as p2;
select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
select lives_ok($$ select public.add_follow_up((select p1 from p), 'liguei, combinamos visita', 'phone', now() + interval '2 days') $$, 'anotação de acompanhamento');
select is((select assigned_to from public.people where id = (select p1 from p)), '22222222-2222-4222-8222-222222222222'::uuid, 'responsável atribuído ao anotar');
select lives_ok($$ select public.merge_people((select p2 from p), (select p1 from p)) $$, 'mesclagem executada');
select pg_temp.logout();
select is((select review_status from public.people where id = (select p2 from p)), 'merged', 'duplicata marcada como merged');
select is((select stage from public.people where id = (select p2 from p)), 'anonymized', 'duplicata anonimizada');
select is((select count(*)::int from public.people_contacts where person_id = (select p2 from p)), 0, 'contato da duplicata apagado');
select is((select count(*)::int from public.referrals where person_id = (select p2 from p) and status not in ('done', 'cancelled')), 0, 'sem encaminhamentos abertos na duplicata');
select ok(exists (select 1 from public.person_events where person_id = (select p1 from p) and event_type = 'merged'), 'evento merged na primária');
select * from finish();
rollback;
