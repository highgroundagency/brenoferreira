-- pgTAP: handle_inbound — resolução por wa_id sem 9º dígito, botões, SAIR, MEUS DADOS, texto livre
begin;
select plan(13);
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
create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2, (select id from public.units where slug = 'curitiba') as unit_id;
insert into public.content_assets (unit_id, key, title, media_type, public_url, rights_ok) values (null, 'video_1', 'Vídeo 1', 'video', 'https://example.org/v1.mp4', true);
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Joana Pires', '41987650071'));
select public.register_person(pg_temp.payload((select c2 from ids), 'Marcos', '41987650072', 'family', '{"contact_name":"Seu Zé"}'));
select pg_temp.logout();
create temp table p as select id as p1 from public.people where client_uuid = (select c1 from ids);
create temp table q as select id as p2 from public.people where client_uuid = (select c2 from ids);

select is(public.phone_variants('+5541987650071'), array['+5541987650071', '+554187650071'], 'variantes com e sem o 9');
select is(public.resolve_person_by_wa((select unit_id from ids), '554187650071', '+554187650071'), (select p1 from p), 'wa_id sem o 9º dígito resolve a pessoa');

-- "Quero continuar" (video_first) => confirma opt-in + video_watched
create temp table r1 as select public.handle_inbound((select unit_id from ids), '554187650071', '+554187650071', 'button', '{"button_id":"video_watched","wamid":"wamid.1"}') as r;
select is((select r->>'action' from r1), 'video_watched', 'botão registrado');
select is((select stage from public.people where id = (select p1 from p)), 'journey_active', 'jornada ativa após o clique');
select ok(exists (select 1 from public.person_events where person_id = (select p1 from p) and event_type = 'video_watched'), 'evento video_watched');
select is((select wa_id from public.people_contacts where person_id = (select p1 from p)), '554187650071', 'wa_id gravado no contato');

-- "Quero receber" (optin_first) => opt-in + vídeo 1 enfileirado como mídia
select public.handle_inbound((select unit_id from ids), '5541987650072', '+5541987650072', 'button', '{"button_id":"optin_yes","wamid":"wamid.2"}');
select is((select stage from public.people where id = (select p2 from q)), 'journey_active', 'opt-in confirmado');
select is((select count(*)::int from public.message_log where person_id = (select p2 from q) and kind = 'media' and status = 'queued'), 1, 'vídeo 1 enfileirado');

-- texto livre => resposta fixa + follow_up
select public.handle_inbound((select unit_id from ids), '554187650071', '+554187650071', 'text', '{"text":"Oi, queria falar com alguém","wamid":"wamid.3"}');
select ok(exists (select 1 from public.referrals where person_id = (select p1 from p) and referral_type = 'follow_up'), 'texto livre gera follow_up');
select is((select count(*)::int from public.message_log where person_id = (select p1 from p) and kind = 'text' and status = 'queued'), 1, 'resposta fixa enfileirada');

-- MEUS DADOS => pedido LGPD
select public.handle_inbound((select unit_id from ids), '554187650071', '+554187650071', 'text', '{"text":"Meus dados","wamid":"wamid.4"}');
select ok(exists (select 1 from public.person_events where person_id = (select p1 from p) and event_type = 'data_request'), 'pedido de dados registrado');

-- SAIR => opt-out, fila bloqueada
select public.handle_inbound((select unit_id from ids), '554187650071', '+554187650071', 'text', '{"text":"sair","wamid":"wamid.5"}');
select is((select stage from public.people where id = (select p1 from p)), 'opted_out', 'SAIR => opted_out');
select is((select count(*)::int from public.message_log where person_id = (select p1 from p) and status = 'queued'), 0, 'nada mais enfileirado após SAIR');
select * from finish();
rollback;
