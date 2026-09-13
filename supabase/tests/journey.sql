-- pgTAP: jornada de vídeos, perguntas de perfil, feedback, pontos, marcos e prêmios
begin;
select plan(25);
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
select public.register_person(pg_temp.payload((select c1 from ids), 'Lia Jornada', '41987650081'));
select pg_temp.logout();
create temp table p as select id as p1, unit_id from public.people where client_uuid = (select c1 from ids);
select pg_temp.mark_sent((select p1 from p));

-- clique "Quero continuar" no vídeo 1: confirma opt-in, inicia jornada, marca passo 1 assistido
select pg_temp.press((select p1 from p), 'video_watched');
select is((select stage from public.people where id = (select p1 from p)), 'journey_active', 'jornada ativa após o 1º clique');
select is((select status from public.person_journeys where person_id = (select p1 from p)), 'active', 'person_journeys criado');
select is((select completed_steps from public.person_journeys where person_id = (select p1 from p)), 1, 'passo 1 contabilizado');
select is((select status from public.journey_progress where person_id = (select p1 from p) and sequence = 1), 'watched', 'passo 1 assistido');
select ok((select next_send_at >= started_at + interval '2 days' from public.person_journeys where person_id = (select p1 from p)), 'próximo passo em D+2');
select is((select count(*)::int from public.message_log where person_id = (select p1 from p) and kind = 'interactive' and status = 'queued'), 1, 'pergunta "o que achou" enfileirada');
select is((select points from public.people where id = (select p1 from p)), 10, '10 pontos por vídeo assistido');
select pg_temp.mark_sent((select p1 from p));
select pg_temp.press((select p1 from p), 'fb_3');
select is((select feedback_score::int from public.journey_progress where person_id = (select p1 from p) and sequence = 1), 3, 'feedback registrado');
select is((select points from public.people where id = (select p1 from p)), 15, '+5 pontos por feedback');

-- passo 2 sem vídeo publicado => pulado; passo 3 com vídeo => template da jornada com header de vídeo
select pg_temp.advance_now((select p1 from p));
select is((select status from public.journey_progress where person_id = (select p1 from p) and sequence = 2), 'skipped', 'passo sem vídeo publicado é pulado');
update public.content_assets set active = true, rights_ok = true, public_url = 'https://cdn.example/v.mp4' where key like 'video_%';
select pg_temp.advance_now((select p1 from p));
select is((select template_name from public.message_log where person_id = (select p1 from p) and status = 'queued' and kind = 'template' order by created_at desc limit 1), 'transtornar_jornada_v1', 'passo 3 enviado como template');
select ok((select payload->>'header_video_link' is not null and payload->'body_params'->>1 = 'A Bíblia no dia a dia' from public.message_log where person_id = (select p1 from p) and status = 'queued' and kind = 'template' order by created_at desc limit 1), 'template com vídeo no header e título no corpo');
select pg_temp.mark_sent((select p1 from p));
select pg_temp.press((select p1 from p), 'video_watched');
select is((select completed_steps from public.person_journeys where person_id = (select p1 from p)), 2, '2 passos concluídos');

-- passo 4 (vídeo) e passo 5 (pergunta de renda)
select pg_temp.advance_now((select p1 from p)); select pg_temp.mark_sent((select p1 from p)); select pg_temp.press((select p1 from p), 'video_watched');
select pg_temp.advance_now((select p1 from p));
select is((select template_name from public.message_log where person_id = (select p1 from p) and status = 'queued' and kind = 'template' order by created_at desc limit 1), 'transtornar_renda_v1', 'pergunta de renda enviada');
select pg_temp.mark_sent((select p1 from p));
select pg_temp.press((select p1 from p), 'income_1_3_mw');
select is((select income_range from public.people where id = (select p1 from p)), '1_3_mw', 'renda registrada pela resposta');
select is((select status from public.journey_progress where person_id = (select p1 from p) and sequence = 5), 'answered', 'pergunta marcada como respondida');

-- passo 6 assistido => 4 passos concluídos => marco "7 dias": Bíblia, estágio day7_done, entrega e mensagem
select pg_temp.advance_now((select p1 from p)); select pg_temp.mark_sent((select p1 from p)); select pg_temp.press((select p1 from p), 'video_watched');
select is((select completed_steps from public.person_journeys where person_id = (select p1 from p)), 4, '4 passos concluídos');
select ok(exists (select 1 from public.reward_grants g join public.reward_rules r on r.id = g.rule_id where g.person_id = (select p1 from p) and r.key = 'day7'), 'prêmio day7 concedido');
select is((select stage from public.people where id = (select p1 from p)), 'day7_done', 'estágio day7_done');
select ok(exists (select 1 from public.delivery_orders where person_id = (select p1 from p) and kind = 'reward' and item_code = 'Bíblia'), 'entrega da Bíblia agendada');
select ok(exists (select 1 from public.message_log where person_id = (select p1 from p) and kind = 'text' and payload->>'text' like 'Parabéns%'), 'mensagem de parabéns enfileirada');

-- pergunta de igreja e convites
select pg_temp.advance_now((select p1 from p)); select pg_temp.mark_sent((select p1 from p)); select pg_temp.press((select p1 from p), 'video_watched');
select pg_temp.advance_now((select p1 from p)); select pg_temp.mark_sent((select p1 from p));
select pg_temp.press((select p1 from p), 'church_yes');
select ok(exists (select 1 from public.referrals where person_id = (select p1 from p) and referral_type = 'church_connection'), 'quer conhecer igreja => encaminhamento');
select ok(exists (select 1 from public.consents where person_id = (select p1 from p) and purpose = 'share_with_church' and granted), 'consentimento de compartilhar com igreja');

-- SAIR encerra a jornada
select public.handle_inbound((select unit_id from p), (select regexp_replace(phone_e164, '\D', '', 'g') from public.people_contacts where person_id = (select p1 from p)), (select phone_e164 from public.people_contacts where person_id = (select p1 from p)), 'text', '{"text":"SAIR","wamid":"w9"}');
select pg_temp.advance_now((select p1 from p));
select is((select status from public.person_journeys where person_id = (select p1 from p)), 'stopped', 'SAIR encerra a jornada');
select is((select count(*)::int from public.message_log where person_id = (select p1 from p) and status = 'queued'), 0, 'nada enfileirado após SAIR');
select * from finish();
rollback;
