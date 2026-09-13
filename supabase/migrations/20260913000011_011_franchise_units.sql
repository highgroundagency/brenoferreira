-- 011 — Fase 4 (franquia): abertura de unidades clonando catálogos globais, importação de bairros de outras cidades,
-- comparação entre unidades e i18n por unidade.

-- clone_unit_defaults ganha os catálogos das fases 2a-3
create or replace function public.clone_unit_defaults(p_new_unit_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_role('global_admin');
  insert into public.teams (unit_id, kind, name, active)
  select p_new_unit_id, k.kind, k.name, k.kind in ('central', 'basic_food', 'follow_up', 'strategy')
  from (values ('central', 'Central'), ('basic_food', 'Cesta básica'), ('follow_up', 'Acompanhamento'), ('strategy', 'Estratégia'),
               ('home_items', 'Itens de casa'), ('education', 'Educação'), ('employment', 'Trabalho'), ('logistics', 'Logística')) as k(kind, name)
  on conflict (unit_id, kind) do nothing;
  insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type, auto_triage, active)
  select p_new_unit_id, name, priority, condition, target_team_kind, referral_type, auto_triage, active from public.routing_rules where unit_id is null;
  insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables)
  select p_new_unit_id, name, language, category, 'pending', header_type, body_text, buttons, variables from public.message_templates where unit_id is null
  on conflict do nothing;
  insert into public.journey_steps (unit_id, journey_key, sequence, day_offset, title, template_name, content_key, question_kind, audience_segment, active)
  select p_new_unit_id, journey_key, sequence, day_offset, title, template_name, content_key, question_kind, audience_segment, active from public.journey_steps where unit_id is null
  on conflict do nothing;
  insert into public.reward_rules (unit_id, key, name, condition_type, threshold, item, stage_on_earn, message_text, active)
  select p_new_unit_id, key, name, condition_type, threshold, item, stage_on_earn, message_text, active from public.reward_rules where unit_id is null
  on conflict do nothing;
  insert into public.point_rules (unit_id, event_type, points, active)
  select p_new_unit_id, event_type, points, active from public.point_rules where unit_id is null
  on conflict do nothing;
  insert into public.supporter_eligibility_rules (unit_id, name, condition, priority, active)
  select p_new_unit_id, name, condition, priority, active from public.supporter_eligibility_rules where unit_id is null;
  insert into public.catalog_items (unit_id, code, name, category, active)
  select p_new_unit_id, code, name, category, active from public.catalog_items where unit_id is null
  on conflict do nothing;
end $$;

-- Abre uma unidade nova: cria a cidade se preciso, vincula os bairros, clona catálogos e semeia o texto de consentimento
create or replace function public.create_unit(p_slug text, p_name text, p_city_name text, p_state text, p_ibge_code text default null,
                                              p_timezone text default 'America/Sao_Paulo', p_locale text default 'pt-BR', p_country char(2) default 'BR') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_city uuid; v_consent jsonb;
begin
  perform public.assert_role('global_admin');
  if exists (select 1 from public.units where slug = lower(p_slug)) then raise exception 'unit_slug_taken'; end if;
  insert into public.units (slug, name, country_code, timezone, locale) values (lower(p_slug), p_name, p_country, p_timezone, p_locale) returning id into v_unit;
  select id into v_city from public.cities where (p_ibge_code is not null and ibge_code = p_ibge_code)
    or (p_ibge_code is null and public.normalize_text(name) = public.normalize_text(p_city_name) and state = upper(p_state) and country_code = p_country);
  if v_city is null then
    insert into public.cities (name, state, country_code, ibge_code) values (p_city_name, upper(p_state), p_country, p_ibge_code) returning id into v_city;
  end if;
  insert into public.unit_neighborhoods (unit_id, neighborhood_id) select v_unit, n.id from public.neighborhoods n where n.city_id = v_city on conflict do nothing;
  perform public.clone_unit_defaults(v_unit);
  select value into v_consent from public.app_settings a join public.units u on u.id = a.unit_id where a.key = 'consent_text_v1' and u.slug = 'curitiba';
  if v_consent is not null then
    insert into public.app_settings (unit_id, key, value, is_public) values (v_unit, 'consent_text_v1', v_consent, true) on conflict do nothing;
  end if;
  insert into public.event_thresholds (unit_id, neighborhood_id, target) values (v_unit, null, 2000) on conflict do nothing;
  insert into public.audit_log (unit_id, actor_id, actor_role, action, table_name, row_id)
  values (v_unit, auth.uid(), public.auth_role(), 'create_unit', 'units', v_unit);
  return v_unit;
end $$;

-- Importa bairros de uma cidade (lista oficial local): [{"name":"...","aliases":["..."],"region":"..."}]
create or replace function public.import_neighborhoods(p_city_id uuid, p_rows jsonb, p_unit_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; v_id uuid; v_new integer := 0; v_existing integer := 0;
begin
  perform public.assert_role('global_admin');
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(r->>'name', '') = '' then continue; end if;
    select id into v_id from public.neighborhoods where city_id = p_city_id and normalized_name = public.normalize_text(r->>'name');
    if v_id is null then
      insert into public.neighborhoods (city_id, name, normalized_name, aliases, region)
      values (p_city_id, r->>'name', public.normalize_text(r->>'name'),
              coalesce((select array_agg(public.normalize_text(x)) from jsonb_array_elements_text(coalesce(r->'aliases', '[]'::jsonb)) x), '{}'), nullif(r->>'region', ''))
      returning id into v_id;
      v_new := v_new + 1;
    else
      v_existing := v_existing + 1;
    end if;
    if p_unit_id is not null then
      insert into public.unit_neighborhoods (unit_id, neighborhood_id) values (p_unit_id, v_id) on conflict do nothing;
    end if;
  end loop;
  return jsonb_build_object('created', v_new, 'existing', v_existing);
end $$;

-- Comparação entre unidades (admin global); cada unidade só enxerga a si mesma pela RLS de mv_impact
create or replace view public.v_units_comparison with (security_invoker = true) as
  select u.id as unit_id, u.slug, u.name, u.locale, u.active,
    (select count(*) from public.profiles p where p.unit_id = u.id and p.active) as members,
    (select count(*) from public.unit_neighborhoods un where un.unit_id = u.id) as neighborhoods,
    m.people_registered, m.decisions_without_record, m.journey_active, m.reached_day7, m.reached_day16,
    m.church_connected, m.food_baskets_delivered, m.courses_completed, m.people_hired,
    m.events_done, m.active_supporters, m.contributions_12m,
    case when m.people_registered > 0 then round(100.0 * m.reached_day7 / m.people_registered, 1) end as pct_day7,
    u.created_at
  from public.units u
  left join public.mv_impact m on m.unit_id = u.id
  where public.can_read_unit(u.id);

grant execute on function public.create_unit(text, text, text, text, text, text, text, char), public.import_neighborhoods(uuid, jsonb, uuid) to authenticated;
grant execute on all functions in schema public to service_role;
