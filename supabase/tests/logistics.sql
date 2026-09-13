-- pgTAP: programa de cesta básica por 3 meses, entregas, avisos e KPI
begin;
select plan(12);
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

create temp table ids as select gen_random_uuid() as c1;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Família Cesta', '41987650091'));
select pg_temp.logout();
create temp table p as select pe.id as p1, pe.unit_id, (select r.id from public.referrals r where r.person_id = pe.id and r.referral_type = 'basic_food') as ref
  from public.people pe where pe.client_uuid = (select c1 from ids);
select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
create temp table prog as select public.start_assistance_program((select ref from p)) as id;
select is((select planned_deliveries from public.assistance_programs where id = (select id from prog)), 3, '3 meses => 3 entregas');
select is((select count(*)::int from public.delivery_orders where program_id = (select id from prog)), 3, '3 entregas agendadas');
select is((select status from public.referrals where id = (select ref from p)), 'in_progress', 'encaminhamento em atendimento');
select throws_ok($$ select public.start_assistance_program((select ref from p)) $$, 'program_already_active_for_household', 'um programa ativo por domicílio');
create temp table d1 as select id from public.delivery_orders where program_id = (select id from prog) order by scheduled_for limit 1;
select lives_ok($$ select public.delivery_transition((select id from d1), 'out_for_delivery') $$, 'saiu para entrega');
select is((select count(*)::int from public.message_log where person_id = (select p1 from p) and template_name = 'transtornar_entrega_v1' and status = 'queued'), 1, 'aviso de entrega (UTILITY) enfileirado');
select is((select pricing_category from public.message_log where person_id = (select p1 from p) and template_name = 'transtornar_entrega_v1' limit 1), 'utility', 'categoria utility');
select lives_ok($$ select public.delivery_transition((select id from d1), 'delivered', 'entregue à Maria') $$, 'entregue');
select is((select completed_deliveries from public.assistance_programs where id = (select id from prog)), 1, '1 entrega concluída');
select throws_ok($$ select public.delivery_transition((select id from d1), 'picking') $$, 'invalid_transition delivered -> picking', 'transição inválida');
update public.delivery_orders set status = 'out_for_delivery', dispatched_at = now() where program_id = (select id from prog) and status = 'scheduled';
select public.delivery_transition(id, 'delivered') from public.delivery_orders where program_id = (select id from prog) and status = 'out_for_delivery';
select is((select status from public.assistance_programs where id = (select id from prog)), 'completed', 'programa concluído após todas as entregas');
select is((select status from public.referrals where id = (select ref from p)), 'done', 'encaminhamento concluído');
select pg_temp.logout();
select * from finish();
rollback;
