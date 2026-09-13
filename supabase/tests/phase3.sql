-- pgTAP: Fase 3 — limiar do bairro, evento, convites segmentados, RSVP, check-in, mantenedores, benefícios e carteirinha
begin;
select plan(28);
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

create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2,
  (select id from public.units where slug = 'curitiba') as unit_id,
  (select id from public.neighborhoods where normalized_name = 'xaxim') as nbh_id;

-- meta baixa no Xaxim para o gatilho disparar com poucos cadastros
insert into public.event_thresholds (unit_id, neighborhood_id, target) select unit_id, nbh_id, 2 from ids;

select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Empresária Ana', '41987650121', 'self', '{"occupation_area":"autônomo/empresário"}'));
select public.register_person(pg_temp.payload((select c2 from ids), 'Vizinho Beto', '41987650122'));
select pg_temp.logout();
create temp table p as select (select id from public.people where client_uuid = (select c1 from ids)) as p1, (select id from public.people where client_uuid = (select c2 from ids)) as p2;

select is((select profile_segment from public.people where id = (select p1 from p)), 'business', 'empresário vira segmento business no cadastro');

-- gatilho: 2 cadastros atingem a meta => evento em rascunho e notificações
create temp table th as select public.check_event_thresholds() as r;
select is((select (r->>'events_created')::int from th), 1, 'meta atingida cria 1 evento em rascunho');
select ok(exists (select 1 from public.events where neighborhood_id = (select nbh_id from ids) and status = 'draft' and threshold_reached), 'evento do bairro criado');
select ok(exists (select 1 from public.event_thresholds where neighborhood_id = (select nbh_id from ids) and reached_at is not null), 'limiar marcado como atingido');
select ok(exists (select 1 from public.notifications where kind = 'event_created'), 'liderança notificada');
select is((select (public.check_event_thresholds()->>'events_created')::int), 0, 'não recria o evento na segunda checagem');

create temp table e as select id from public.events where neighborhood_id = (select nbh_id from ids) limit 1;
update public.events set starts_at = now() + interval '10 days', location = 'Praça do Xaxim', status = 'planned' where id = (select id from e);

select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
select is((select count(*)::int from public.event_audience((select id from e))), 2, 'público do evento: as 2 pessoas do bairro');

-- convites só para quem consentiu marketing_events
create temp table inv1 as select public.invite_to_event((select id from e)) as r;
select is((select (r->>'invited')::int from inv1), 0, 'sem consentimento de convites, ninguém é convidado');
select is((select (r->>'skipped')::int from inv1), 2, '2 pessoas puladas por falta de consentimento');
select pg_temp.logout();

select public.journey_answer((select p1 from p), 'events_optin', 'yes');
select public.journey_answer((select p2 from p), 'events_optin', 'no');
select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
create temp table inv2 as select public.invite_to_event((select id from e)) as r;
select is((select (r->>'invited')::int from inv2), 1, 'só quem aceitou convites recebe');
select is((select status from public.events where id = (select id from e)), 'inviting', 'evento passa a inviting');
select ok(exists (select 1 from public.message_log where person_id = (select p1 from p) and template_name = 'transtornar_evento_v1' and status = 'queued'), 'template do evento enfileirado');
select ok((select checkin_code is not null from public.event_invitations where person_id = (select p1 from p)), 'código de check-in gerado');
select is((select (public.invite_to_event((select id from e))->>'invited')::int), 0, 'não convida a mesma pessoa duas vezes');
select pg_temp.logout();

-- RSVP pelo botão do WhatsApp e check-in pelo código
select public.handle_inbound((select unit_id from ids), (select regexp_replace(phone_e164, '\D', '', 'g') from public.people_contacts where person_id = (select p1 from p)),
  (select phone_e164 from public.people_contacts where person_id = (select p1 from p)), 'button', '{"button_id":"rsvp_yes","wamid":"w-rsvp"}');
select is((select rsvp from public.event_invitations where person_id = (select p1 from p)), 'yes', 'RSVP sim registrado');
select ok(exists (select 1 from public.message_log where person_id = (select p1 from p) and payload->>'text' like '%código de entrada%'), 'código enviado no RSVP sim');

select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
create temp table ci as select public.event_checkin((select checkin_code from public.event_invitations where person_id = (select p1 from p))) as r;
select is((select (r->>'already')::boolean from ci), false, 'check-in realizado');
select ok((select checked_in_at is not null from public.event_invitations where person_id = (select p1 from p)), 'check-in gravado');
select is((select points from public.people where id = (select p1 from p)), 25, 'pontos: 5 da resposta de perfil + 20 do check-in');
select is((select (public.event_checkin((select checkin_code from public.event_invitations where person_id = (select p1 from p)))->>'already')::boolean), true, 'segundo check-in é idempotente');

-- mantenedores: candidata elegível, funil e carteirinha
select ok(exists (select 1 from public.supporter_candidates((select unit_id from ids)) where person_id = (select p1 from p)), 'empresária aparece como candidata a mantenedora');
create temp table s as select public.create_supporter((select p1 from p), 'invited') as id;
select public.supporter_transition((select id from s), 'active', 'mensal', 200);
select is((select stage from public.people where id = (select p1 from p)), 'supporter', 'estágio vira supporter');
select ok(exists (select 1 from public.consents where person_id = (select p1 from p) and purpose = 'benefits_club' and granted), 'consentimento do clube de benefícios');
insert into public.contributions (unit_id, supporter_id, amount, method) select (select unit_id from ids), (select id from s), 200, 'pix';
select is((select monthly_amount from public.v_supporter_funnel where status = 'active'), 200::numeric, 'funil soma a contribuição mensal');

-- benefícios: parceiro, resgate e carteirinha pública
insert into public.companies (unit_id, name, roles, source) select (select unit_id from ids), 'Farmácia Parceira', '{benefit_partner}'::text[], 'partner';
insert into public.benefits (unit_id, company_id, title, rules) select (select unit_id from ids), (select id from public.companies where name = 'Farmácia Parceira'), '10% em medicamentos', 'apresentar a carteirinha';
create temp table card as select card_code from public.supporters where id = (select id from s);
select lives_ok($$ select public.redeem_benefit((select card_code from card), (select id from public.benefits limit 1), 'balcão') $$, 'benefício resgatado pelo código da carteirinha');
select is((select count(*)::int from public.benefit_redemptions), 1, 'resgate registrado');
select pg_temp.logout();
select is((select (public.supporter_card((select card_code from card))->>'name')), 'Empresária', 'carteirinha pública mostra só o primeiro nome');
select is((select jsonb_array_length(public.supporter_card((select card_code from card))->'benefits')), 1, 'carteirinha lista os benefícios ativos');
select * from finish();
rollback;
