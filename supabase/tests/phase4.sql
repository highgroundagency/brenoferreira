-- pgTAP: Fase 4 — abertura de unidade (franquia), catálogos clonados, isolamento e importação de bairros
begin;
select plan(15);
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

select pg_temp.login('55555555-5555-4555-8555-555555555555', 'global_admin@test');
create temp table u as select public.create_unit('sao-jose', 'Transtornar São José dos Pinhais', 'São José dos Pinhais', 'PR', '4125506') as id;
select ok((select id is not null from u), 'unidade criada pelo admin global');
select is((select slug from public.units where id = (select id from u)), 'sao-jose', 'slug gravado');
select ok(exists (select 1 from public.cities where ibge_code = '4125506'), 'cidade criada');
select is((select count(*)::int from public.teams where unit_id = (select id from u)), 8, '8 times clonados');
select is((select count(*)::int from public.teams where unit_id = (select id from u) and active), 4, '4 times ativos por padrão');
select is((select count(*)::int from public.routing_rules where unit_id = (select id from u)), (select count(*)::int from public.routing_rules where unit_id is null), 'regras de roteamento clonadas');
select is((select count(*)::int from public.journey_steps where unit_id = (select id from u)), (select count(*)::int from public.journey_steps where unit_id is null), 'passos da jornada clonados');
select is((select count(*)::int from public.reward_rules where unit_id = (select id from u)), 2, 'marcos clonados');
select ok(exists (select 1 from public.app_settings where unit_id = (select id from u) and key = 'consent_text_v1' and is_public), 'texto de consentimento semeado');
select ok(exists (select 1 from public.message_templates where unit_id = (select id from u) and status = 'pending'), 'templates clonados como pendentes de aprovação');

-- importação de bairros da nova cidade
create temp table imp as select public.import_neighborhoods((select id from public.cities where ibge_code = '4125506'),
  '[{"name":"Centro","aliases":["centro sjp"]},{"name":"Afonso Pena"},{"name":"Centro"}]'::jsonb, (select id from u)) as r;
select is((select (r->>'created')::int from imp), 2, '2 bairros criados (duplicata ignorada)');
select is((select count(*)::int from public.unit_neighborhoods where unit_id = (select id from u)), 2, 'bairros vinculados à unidade');
select throws_ok($$ select public.create_unit('sao-jose', 'Duplicada', 'Curitiba', 'PR') $$, 'unit_slug_taken', 'slug duplicado é rejeitado');
select pg_temp.logout();

-- unit_admin de Curitiba não abre unidade nem enxerga a nova na comparação
select pg_temp.login('44444444-4444-4444-8444-444444444444', 'unit_admin@test');
select throws_ok($$ select public.create_unit('outra', 'Outra', 'Colombo', 'PR') $$, '42501', null, 'unit_admin não abre unidades');
select is((select count(*)::int from public.v_units_comparison), 1, 'unit_admin só vê a própria unidade na comparação');
select pg_temp.logout();
select * from finish();
rollback;
