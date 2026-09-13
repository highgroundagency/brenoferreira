-- 012 — Endurecimento pós-advisors: as funções criadas nas migrations 009-011 nasceram depois do
-- `revoke ... from public, anon` da 008 e ficaram executáveis pelo papel `anon` (PostgREST /rest/v1/rpc/*).
-- Aqui a lista de execução é refeita do zero, funções sem checagem própria ganham guarda de papel,
-- a mv_impact sai da API (as visões passam a filtrar com os direitos do dono) e o search_path é fixado.

-- ---------------------------------------------------------------------------
-- 1. Guardas nas funções que dependiam só do grant
-- ---------------------------------------------------------------------------

-- Público-alvo do evento: só equipe da unidade dona do evento.
create or replace function public.event_audience(p_event_id uuid) returns setof public.people
language plpgsql stable security definer set search_path = public as $$
declare e record; seg jsonb;
begin
  select * into e from public.events where id = p_event_id;
  if e.id is null then return; end if;
  if not (public.is_unit_staff() and public.can_read_unit(e.unit_id)) then raise insufficient_privilege; end if;
  seg := coalesce(e.target_segment, '{}'::jsonb);
  return query
    select p.* from public.people p
    where p.unit_id = e.unit_id
      and p.stage not in ('opted_out', 'anonymized')
      and p.review_status <> 'merged'
      and (not (seg ? 'neighborhood_ids') or p.neighborhood_id::text in (select jsonb_array_elements_text(seg->'neighborhood_ids')))
      and (not (seg ? 'age_ranges') or p.age_range in (select jsonb_array_elements_text(seg->'age_ranges')))
      and (not (seg ? 'income_ranges') or p.income_range in (select jsonb_array_elements_text(seg->'income_ranges')))
      and (not (seg ? 'profile_segments') or p.profile_segment in (select jsonb_array_elements_text(seg->'profile_segments')))
      and (not (seg ? 'stages') or p.stage in (select jsonb_array_elements_text(seg->'stages')));
end $$;

-- Candidatos a mantenedor: nome completo é PII; a unidade pedida tem de ser a de quem pergunta.
create or replace function public.supporter_candidates(p_unit_id uuid) returns table (person_id uuid, full_name text, rule_id uuid, rule_name text)
language sql stable security definer set search_path = public as $$
  select distinct on (p.id) p.id, pc.full_name, r.id, r.name
  from public.people p
  join public.people_contacts pc on pc.person_id = p.id
  join public.supporter_eligibility_rules r on r.active
    and r.unit_id is not distinct from (case when exists (select 1 from public.supporter_eligibility_rules x where x.unit_id = p_unit_id and x.active) then p_unit_id else null end)
  where p.unit_id = p_unit_id
    and public.is_unit_staff() and public.can_read_unit(p_unit_id)
    and p.stage not in ('opted_out', 'anonymized') and p.review_status <> 'merged'
    and not exists (select 1 from public.supporters s where s.person_id = p.id)
    and (
      (r.condition ? 'profile_segment_in' and p.profile_segment in (select jsonb_array_elements_text(r.condition->'profile_segment_in')))
      or (r.condition ? 'income_in' and p.income_range in (select jsonb_array_elements_text(r.condition->'income_in')))
      or (r.condition ? 'stage_in' and p.stage in (select jsonb_array_elements_text(r.condition->'stage_in')))
      or (r.condition ? 'occupation_area_in' and p.occupation_area in (select jsonb_array_elements_text(r.condition->'occupation_area_in')))
      or (r.condition ? 'min_points' and p.points >= (r.condition->>'min_points')::int)
    )
  order by p.id, r.priority
$$;

-- Sugestão de igreja: só equipe da unidade da pessoa.
create or replace function public.suggest_church(p_person_id uuid) returns setof public.churches
language sql stable security definer set search_path = public as $$
  select c.* from public.churches c join public.people p on p.unit_id = c.unit_id
  where p.id = p_person_id and c.active and public.is_unit_staff() and public.can_read_unit(p.unit_id)
  order by (c.neighborhood_id = p.neighborhood_id) desc, c.name limit 5
$$;

-- Refresh do impacto: cron (sem perfil) ou central/admin; nunca um evangelista.
create or replace function public.refresh_impact() returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.auth_role() is not null and public.auth_role() not in ('central', 'unit_admin', 'global_admin') then
    raise insufficient_privilege using message = 'papel não autorizado para esta operação';
  end if;
  refresh materialized view concurrently public.mv_impact;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Execução: zera tudo e reconcede só o que o app usa
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from authenticated;

-- helpers chamados dentro das políticas de RLS e do formulário
grant execute on function public.auth_unit_id(), public.auth_role(), public.auth_team_ids(), public.is_unit_staff(),
  public.is_team_kind(text[]), public.can_read_unit(uuid), public.can_write_unit(uuid),
  public.normalize_text(text), public.normalize_e164(text), public.find_neighborhood(uuid, text)
  to authenticated;

-- RPCs do app (cada uma valida papel/unidade no corpo)
grant execute on function public.register_person(jsonb), public.record_decision_tally(uuid, boolean),
  public.get_my_registrations(), public.get_team_queue(text), public.open_person_record(uuid),
  public.referral_transition(uuid, text, text), public.mark_duplicate(uuid, uuid), public.confirm_distinct_person(uuid),
  public.merge_people(uuid, uuid), public.anonymize_person(uuid, text),
  public.add_follow_up(uuid, text, text, timestamptz), public.start_assistance_program(uuid, integer, integer),
  public.delivery_transition(uuid, text, text),
  public.create_invite(text, text, uuid), public.accept_invite(text), public.clone_unit_defaults(uuid),
  public.enroll_person(uuid, uuid, uuid, uuid), public.enrollment_transition(uuid, text, text),
  public.import_companies(jsonb, text), public.refer_to_job(uuid, uuid, uuid), public.placement_transition(uuid, text, text),
  public.grant_consent(uuid, text, text), public.suggest_church(uuid), public.connect_church(uuid, uuid, text),
  public.fulfill_home_item(uuid, text), public.add_stock(text, integer, text, text),
  public.import_legacy_people(jsonb, text), public.activate_legacy_person(uuid, text), public.refresh_impact(),
  public.create_event(text, text, uuid, jsonb), public.invite_to_event(uuid, integer), public.event_audience(uuid),
  public.event_checkin(text), public.supporter_candidates(uuid), public.create_supporter(uuid, text, jsonb),
  public.supporter_transition(uuid, text, text, numeric), public.record_contribution(uuid, numeric, text, text),
  public.redeem_benefit(text, uuid, text), public.supporter_card(text),
  public.create_unit(text, text, text, text, text, text, text, char), public.import_neighborhoods(uuid, jsonb, uuid)
  to authenticated;

-- Sem sessão: só a página de convite e a carteirinha pública.
grant execute on function public.get_invite(text), public.normalize_text(text), public.supporter_card(text) to anon;

-- Edge Functions e pg_cron
grant execute on all functions in schema public to service_role;

-- ---------------------------------------------------------------------------
-- 3. mv_impact fora da API: as visões filtram com os direitos do dono
-- ---------------------------------------------------------------------------
revoke select on public.mv_impact from anon, authenticated;
alter view public.v_impact_by_unit set (security_invoker = false);
alter view public.v_units_comparison set (security_invoker = false);
grant select on public.v_impact_by_unit, public.v_units_comparison to authenticated;

-- ---------------------------------------------------------------------------
-- 4. search_path fixo nas funções que ainda dependiam do caller
-- ---------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    left join pg_depend d on d.objid = p.oid and d.deptype = 'e'
    where n.nspname = 'public' and d.objid is null
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public, extensions', f.sig);
  end loop;
end $$;

-- pg_net fora do schema public quando a extensão aceitar (no Supabase ela mora em "net"; ignorar se não for relocável)
do $$
begin
  if exists (select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_net' and n.nspname = 'public')
     and exists (select 1 from pg_namespace where nspname = 'extensions') then
    begin
      execute 'alter extension pg_net set schema extensions';
    exception when others then
      raise notice 'pg_net não é relocável: %', sqlerrm;
    end;
  end if;
end $$;
