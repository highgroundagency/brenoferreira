-- pgTAP: retenção (silêncio => inativo + contato humano; opt-out => anonimização), quiet hours e vault
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
create temp table ids as select gen_random_uuid() as c1, gen_random_uuid() as c2;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Silencioso', '41987650061'));
select public.register_person(pg_temp.payload((select c2 from ids), 'Saiu', '41987650062'));
select pg_temp.logout();
update public.people set first_contact_sent_at = now() - interval '17 days' where client_uuid = (select c1 from ids);
select public.opt_out_person((select id from public.units where slug = 'curitiba'), '+5541987650062', 'SAIR');
update public.people set stage_changed_at = now() - interval '31 days' where client_uuid = (select c2 from ids);

create temp table res as select public.run_retention_policy() as r;
select is((select (r->>'inactivated')::int from res), 1, '1 pessoa inativada por silêncio');
select is((select (r->>'anonymized')::int from res), 1, '1 pessoa anonimizada por opt-out');
select is((select stage from public.people where client_uuid = (select c1 from ids)), 'inactive', 'silêncio => inactive (nunca anonimização)');
select ok(exists (select 1 from public.referrals r join public.people p on p.id = r.person_id where p.client_uuid = (select c1 from ids) and r.referral_type = 'follow_up'), 'silêncio => encaminhamento para contato humano');
select is((select stage from public.people where client_uuid = (select c2 from ids)), 'anonymized', 'opt-out há 30 dias => anonimizada');

-- quiet hours (America/Sao_Paulo): 22:00 local => 08:00 do dia seguinte; 10:00 => inalterado
select is(public.next_send_slot((select id from public.units where slug = 'curitiba'), '2026-09-14 22:00-03'::timestamptz), '2026-09-15 08:00-03'::timestamptz, '22h => 08h do dia seguinte');
select is(public.next_send_slot((select id from public.units where slug = 'curitiba'), '2026-09-14 07:30-03'::timestamptz), '2026-09-14 08:00-03'::timestamptz, '07:30 => 08h');
select is(public.next_send_slot((select id from public.units where slug = 'curitiba'), '2026-09-14 10:00-03'::timestamptz), '2026-09-14 10:00-03'::timestamptz, '10h => inalterado');
select is((select count(*)::int from vault.decrypted_secrets where name = 'edge_shared_secret'), 1, 'segredo edge_shared_secret existe no vault');
select * from finish();
rollback;
