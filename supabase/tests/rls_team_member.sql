-- pgTAP: membro do time de cesta básica só vê sua fila (com endereço, sem observação/e-mail); perfil inativo => nada
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
select public.register_person(pg_temp.payload((select c1 from ids), 'Carlos Lima', '41987650021', 'self', '{"email": "carlos@x.com"}'));
select pg_temp.logout();

select pg_temp.login('33333333-3333-4333-8333-333333333333', 'basic_food@test');
select is((select count(*)::int from public.people), 0, 'team_member não lê people');
select is((select count(*)::int from public.get_team_queue('basic_food')), 1, 'vê 1 item na fila de cesta básica');
select ok((select (q->>'phone_e164') is not null and (q->'address'->>'street') = 'Rua das Flores' from public.get_team_queue('basic_food') q), 'fila traz telefone e endereço para a entrega');
select ok((select not (q ? 'observation') and not (q ? 'email') from public.get_team_queue('basic_food') q), 'fila não traz observação nem e-mail');
select is((select count(*)::int from public.get_team_queue('strategy')), 0, 'não vê a fila de outro time');
select is((select count(*)::int from public.referrals), 1, 'select direto em referrals limitado ao próprio time');
select lives_ok($$ select public.referral_transition((select (q->>'id')::uuid from public.get_team_queue('basic_food') q), 'in_progress', 'assumi') $$, 'assume o item');
select pg_temp.logout();
update public.profiles set active = false where id = '33333333-3333-4333-8333-333333333333';
select pg_temp.login('33333333-3333-4333-8333-333333333333', 'basic_food@test');
select is((select count(*)::int from public.get_team_queue('basic_food')), 0, 'perfil inativo não vê a fila');
select is((select count(*)::int from public.referrals), 0, 'perfil inativo não lê referrals');
select pg_temp.logout();
select * from finish();
rollback;
