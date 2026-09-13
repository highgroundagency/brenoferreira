-- pgTAP: register_person — transação, idempotência, dedup suave por telefone, household, consentimentos, 1º contato, menor
begin;
select plan(22);
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
create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2, gen_random_uuid() as c3, gen_random_uuid() as c4;

select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
create temp table r1 as select public.register_person(pg_temp.payload((select c1 from ids), 'João da Silva', '(41) 98765-0001')) as r;
select is((select (r->>'idempotent')::boolean from r1), false, 'primeiro cadastro não é idempotente');
select is((select r->>'review_status' from r1), 'ok', 'sem duplicidade');
select is((select r->>'first_contact' from r1), 'transtornar_video1_v1', 'número próprio + modo video_first => template de vídeo');
select ok((select (r->>'household_id') is not null from r1), 'household criado para endereço fixo');

create temp table r1b as select public.register_person(pg_temp.payload((select c1 from ids), 'João da Silva', '(41) 98765-0001')) as r;
select is((select (r->>'idempotent')::boolean from r1b), true, 'reenvio do mesmo client_uuid é idempotente');
select is((select r->>'person_id' from r1b), (select r->>'person_id' from r1), 'mesmo person_id');

select throws_ok($$ select public.register_person(pg_temp.payload((select c2 from ids), 'Menor', '(41) 98765-0002', 'self', '{"is_adult": false}')) $$,
  'minor_not_allowed', 'menor de 18 é rejeitado');
select throws_ok($$ select public.register_person(pg_temp.payload((select c2 from ids), 'Sem consent', '(41) 98765-0002', 'self', '{"consent": {"accepted": false}}')) $$,
  'consent_required', 'sem consentimento é rejeitado');

-- mesmo telefone, pessoa diferente => possible_duplicate, sem 1º contato
create temp table r2 as select public.register_person(pg_temp.payload((select c2 from ids), 'Maria da Silva', '+55 41 98765-0001')) as r;
select is((select r->>'review_status' from r2), 'possible_duplicate', 'mesmo telefone => possível duplicata');
select ok((select r->>'first_contact' is null from r2), 'possível duplicata não recebe 1º contato');

-- número de familiar => opt-in neutro
create temp table r3 as select public.register_person(pg_temp.payload((select c3 from ids), 'Pedro', '41987650003', 'family', '{"contact_name": "Dona Ana"}')) as r;
select is((select r->>'first_contact' from r3), 'transtornar_optin_v1', 'número de familiar => template neutro de opt-in');

select pg_temp.logout();
-- verificações como postgres
select is((select count(*)::int from public.people where client_uuid in (select c1 from ids)), 1, '1 linha em people para c1');
select is((select count(*)::int from public.children c join public.people p on p.id = c.person_id where p.client_uuid = (select c1 from ids)), 3, '3 filhos');
select is((select count(*)::int from public.needs n join public.people p on p.id = n.person_id where p.client_uuid = (select c1 from ids)), 2, '2 necessidades');
select is((select count(*)::int from public.consents c join public.people p on p.id = c.person_id where p.client_uuid = (select c1 from ids) and c.granted), 3, '3 consentimentos (espiritual, whatsapp, social)');
select is((select count(*)::int from public.referrals r join public.people p on p.id = r.person_id where p.client_uuid = (select c1 from ids)), 5, '5 encaminhamentos');
select is((select count(*)::int from public.message_log m join public.people p on p.id = m.person_id where p.client_uuid = (select c1 from ids) and m.status = 'queued'), 1, '1 mensagem enfileirada');
select is((select p.stage from public.people p where p.client_uuid = (select c1 from ids)), 'first_contact_pending', 'estágio first_contact_pending');
select is((select pc.is_primary from public.people_contacts pc join public.people p on p.id = pc.person_id where p.client_uuid = (select c2 from ids)), false, 'duplicata com is_primary=false');
select is((select p.duplicate_of_person_id from public.people p where p.client_uuid = (select c2 from ids)), (select id from public.people where client_uuid = (select c1 from ids)), 'duplicate_of aponta para a primária');
select is((select pc.phone_e164 from public.people_contacts pc join public.people p on p.id = pc.person_id where p.client_uuid = (select c3 from ids)), '+5541987650003', 'telefone normalizado em E.164');
select is((select m.payload->>'first_name' from public.message_log m join public.people p on p.id = m.person_id where p.client_uuid = (select c3 from ids)), 'Dona', 'mensagem endereçada a quem atende o número');

select * from finish();
rollback;
