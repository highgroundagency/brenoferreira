-- pgTAP: motor de roteamento (apply_routing_rules) — idempotência, fallback para a central, duplicate_household, trigger em needs
begin;
select plan(14);
set local role postgres;

create temp table ctx as
select (select id from public.units where slug = 'curitiba') as unit_id,
       (select id from public.cities where ibge_code = '4106902') as city_id,
       (select n.id from public.neighborhoods n where n.normalized_name = 'xaxim') as nbh_id,
       '11111111-1111-4111-8111-111111111111'::uuid as evangelist_id,
       (select t.id from public.teams t where t.unit_id = (select id from public.units where slug = 'curitiba') and t.kind = 'central') as central_team,
       (select t.id from public.teams t where t.unit_id = (select id from public.units where slug = 'curitiba') and t.kind = 'basic_food') as food_team,
       gen_random_uuid() as p1, gen_random_uuid() as p2, gen_random_uuid() as h1;

select set_config('app.skip_routing', 'on', true);

insert into public.households (id, unit_id, address_hash, neighborhood_id, city_id)
select h1, unit_id, 'hash-casa-1', nbh_id, city_id from ctx;

insert into public.people (id, unit_id, client_uuid, household_id, neighborhood_id, city_id, has_basic_need, children_count, needs_job, occupation_area, registered_by, consent_text_version)
select p1, unit_id, gen_random_uuid(), h1, nbh_id, city_id, true, 3, true, 'cozinha', evangelist_id, 'v1' from ctx;
insert into public.people_contacts (person_id, unit_id, full_name, phone_e164, street, number)
select p1, unit_id, 'João da Silva', '+5541987650001', 'Rua A', '10' from ctx;
insert into public.children (unit_id, person_id, age_band) select unit_id, p1, b from ctx, unnest(array['15_17', '15_17', '12_14']) as b;
insert into public.needs (unit_id, person_id, household_id, need_type) select unit_id, p1, h1, 'food' from ctx;
insert into public.needs (unit_id, person_id, household_id, need_type, item_code) select unit_id, p1, h1, 'furniture', 'cama' from ctx;

select is(public.apply_routing_rules((select p1 from ctx)), 5, 'primeiro roteamento cria 5 encaminhamentos (estratégia, alimento, móvel, educação, trabalho)');
select is((select count(*)::int from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'strategy_review'), 1, 'exatamente 1 strategy_review');
select is((select count(*)::int from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'basic_food'), 1, 'exatamente 1 basic_food');
select is((select r.team_id from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'basic_food'), (select food_team from ctx), 'basic_food vai ao time de cesta básica (ativo, com membro)');
select is((select r.team_id from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'home_items'), (select central_team from ctx), 'home_items cai na central (time inativo)');
select is((select r.team_id from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'strategy_review'), (select central_team from ctx), 'strategy sem membros cai na central');
select is((select count(*)::int from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type in ('education', 'employment')), 2, 'educação e trabalho gerados');
select is((select status from public.needs n, ctx where n.person_id = ctx.p1 and n.need_type = 'food'), 'routed', 'necessidade marcada como roteada');

select is(public.apply_routing_rules((select p1 from ctx)), 0, 'segunda execução é idempotente (0 novos)');
select is((select count(*)::int from public.referrals r, ctx where r.person_id = ctx.p1), 5, 'continua com 5 encaminhamentos');

-- notificações: time sem PII; central com primeiro nome
select ok(exists (select 1 from public.notifications no, ctx where no.team_id = ctx.food_team and no.title not like '%João%'), 'notificação ao time sem nome');
select ok(exists (select 1 from public.notifications no, ctx where no.ref_table = 'people' and no.ref_id = ctx.p1 and no.title like 'João — Xaxim%'), 'notificação à central com primeiro nome e bairro');

-- segunda pessoa na mesma casa com alimento => flag duplicate_household
insert into public.people (id, unit_id, client_uuid, household_id, neighborhood_id, city_id, has_basic_need, registered_by, consent_text_version)
select p2, unit_id, gen_random_uuid(), h1, nbh_id, city_id, true, evangelist_id, 'v1' from ctx;
insert into public.people_contacts (person_id, unit_id, full_name, phone_e164) select p2, unit_id, 'Maria da Silva', '+5541987650002' from ctx;
insert into public.needs (unit_id, person_id, household_id, need_type) select unit_id, p2, h1, 'food' from ctx;
select public.apply_routing_rules((select p2 from ctx));
select ok((select 'duplicate_household' = any(r.flags) from public.referrals r, ctx where r.person_id = ctx.p2 and r.referral_type = 'basic_food'), 'mesma casa => flag duplicate_household');

-- trigger needs_route: nova necessidade fora do skip gera 1 referral novo
select set_config('app.skip_routing', 'off', true);
insert into public.needs (unit_id, person_id, household_id, need_type, item_code) select unit_id, p1, h1, 'appliance', 'geladeira' from ctx;
select is((select count(*)::int from public.referrals r, ctx where r.person_id = ctx.p1 and r.referral_type = 'home_items'), 2, 'trigger needs_route criou o encaminhamento da nova necessidade');

select * from finish();
rollback;
