-- pgTAP: Fase 2b — cursos/matrículas, empresas/vagas/importação, igrejas, estoque de itens, legado, impacto
begin;
select plan(24);
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

create temp table ids as select gen_random_uuid() as c1, (select id from public.units where slug = 'curitiba') as unit_id;
select pg_temp.login('11111111-1111-4111-8111-111111111111', 'evangelist@test');
select public.register_person(pg_temp.payload((select c1 from ids), 'Rita Trabalho', '41987650111', 'self', '{"needs": [{"need_type":"furniture","item_code":"cama"}]}'));
select pg_temp.logout();
create temp table p as select pe.id as p1 from public.people pe where pe.client_uuid = (select c1 from ids);
create temp table refs as select referral_type, id from public.referrals where person_id = (select p1 from p);

select pg_temp.login('22222222-2222-4222-8222-222222222222', 'central@test');
-- importação de empresas com dedup por CNPJ e telefone
create temp table imp as select public.import_companies('[
  {"name":"Padaria Pão Bom","cnpj":"12.345.678/0001-90","sector":"alimentação","contact_name":"Zé","contact_phone":"41 99999-0001","neighborhood":"Xaxim","job_role":"auxiliar de cozinha","area":"cozinha","open_positions":2},
  {"name":"Padaria Pao Bom","cnpj":"12345678000190","contact_phone":"41999990001","job_role":"auxiliar de cozinha"},
  {"name":"Sem CNPJ Ltda","contact_phone":"41 99999-0002","job_role":"vendedor"},
  {"name":"","contact_phone":"x"}
]'::jsonb, 'empresas.csv') as r;
select diag((select r->>'log' from imp));
select is((select (r->>'imported')::int from imp), 3, '3 linhas importadas');
select is((select (r->>'rejected')::int from imp), 1, '1 linha rejeitada (sem nome)');
select is((select count(*)::int from public.companies where legal_id = '12345678000190'), 1, 'CNPJ deduplicado em 1 empresa');
select is((select count(*)::int from public.job_openings jo join public.companies c on c.id = jo.company_id where c.legal_id = '12345678000190'), 1, 'vaga não duplicada');
select is((select open_positions from public.job_openings jo join public.companies c on c.id = jo.company_id where c.legal_id = '12345678000190'), 2, '2 vagas abertas');

-- encaminhar a vaga exige consentimento de compartilhar com empregador
create temp table jo as select jo.id from public.job_openings jo join public.companies c on c.id = jo.company_id where c.legal_id = '12345678000190';
select throws_ok($$ select public.refer_to_job((select p1 from p), (select id from jo), (select id from refs where referral_type = 'employment')) $$, 'consent_share_with_employer_required', 'sem consentimento não encaminha a vaga');
select public.grant_consent((select p1 from p), 'share_with_employer', 'admin');
create temp table pl as select public.refer_to_job((select p1 from p), (select id from jo), (select id from refs where referral_type = 'employment')) as id;
select is((select status from public.job_placements where id = (select id from pl)), 'referred', 'colocação criada');
select public.placement_transition((select id from pl), 'hired', 'começa segunda');
select is((select open_positions from public.job_openings where id = (select id from jo)), 1, 'vaga decrementada ao contratar');
select is((select status from public.referrals where id = (select id from refs where referral_type = 'employment')), 'done', 'encaminhamento de trabalho concluído');

-- curso e matrícula
insert into public.courses (unit_id, name, audience, area, seats, starts_at) values ((select unit_id from ids), 'Auxiliar de cozinha', 'adult', 'cozinha', 1, current_date + 7);
create temp table en as select public.enroll_person((select p1 from p), (select id from public.courses where name = 'Auxiliar de cozinha'), null, (select id from refs where referral_type = 'education')) as id;
select is((select status from public.enrollments where id = (select id from en)), 'enrolled', 'matriculado');
select ok(exists (select 1 from public.message_log where person_id = (select p1 from p) and template_name = 'transtornar_curso_v1'), 'aviso de matrícula enfileirado');
select throws_ok($$ select public.enroll_person('11111111-1111-4111-8111-111111111111'::uuid, (select id from public.courses where name = 'Auxiliar de cozinha')) $$, null, 'turma cheia ou pessoa inválida => erro');
select public.enrollment_transition((select id from en), 'completed', 'certificado 20h');
select is((select status from public.referrals where id = (select id from refs where referral_type = 'education')), 'done', 'encaminhamento de educação concluído');

-- igreja: convite exige consentimento; conexão muda estágio e dá pontos
insert into public.churches (unit_id, name, neighborhood_id, service_times) values ((select unit_id from ids), 'Igreja do Xaxim', (select id from public.neighborhoods where normalized_name = 'xaxim'), 'dom 19h');
select is((select count(*)::int from public.suggest_church((select p1 from p))), 1, 'sugestão de igreja do bairro');
select throws_ok($$ select public.connect_church((select p1 from p), (select id from public.churches where name = 'Igreja do Xaxim'), 'invited') $$, 'consent_share_with_church_required', 'convite exige consentimento');
select public.grant_consent((select p1 from p), 'share_with_church', 'admin');
select lives_ok($$ select public.connect_church((select p1 from p), (select id from public.churches where name = 'Igreja do Xaxim'), 'invited') $$, 'convite enviado');
select ok(exists (select 1 from public.message_log where person_id = (select p1 from p) and template_name = 'transtornar_igreja_convite_v1'), 'template de convite da igreja enfileirado');
update public.people set stage = 'journey_active' where id = (select p1 from p);
select public.connect_church((select p1 from p), (select id from public.churches where name = 'Igreja do Xaxim'), 'connected');
select is((select stage from public.people where id = (select p1 from p)), 'church_connected', 'estágio church_connected');
select is((select points from public.people where id = (select p1 from p)), 20, '20 pontos por conexão com igreja');

-- itens de casa: sem estoque => erro; com estoque => entrega e baixa
select throws_ok($$ select public.fulfill_home_item((select id from refs where referral_type = 'home_items'), 'cama') $$, 'out_of_stock', 'sem estoque');
select public.add_stock('cama', 2, 'donation', 'doação');
select lives_ok($$ select public.fulfill_home_item((select id from refs where referral_type = 'home_items'), 'cama') $$, 'item atendido com estoque');
select is((select quantity from public.inventory_stock where item_code = 'cama' and unit_id = (select unit_id from ids)), 1, 'estoque baixado para 1');

-- pessoas da plataforma legada: sem consentimento, sem mensagem, com contato humano
create temp table leg as select public.import_legacy_people('[{"full_name":"Antigo Aluno","phone":"41987650199","neighborhood":"Xaxim"},{"full_name":"Repetido","phone":"41987650111","neighborhood":"Xaxim"}]'::jsonb, 'legado.csv') as r;
select is((select (r->>'imported')::int from leg), 1, '1 importado (telefone repetido rejeitado)');
select is((select count(*)::int from public.message_log m join public.people pe on pe.id = m.person_id where pe.source = 'legacy_platform'), 0, 'nenhuma mensagem para importados sem consentimento');
select pg_temp.logout();
select * from finish();
rollback;
