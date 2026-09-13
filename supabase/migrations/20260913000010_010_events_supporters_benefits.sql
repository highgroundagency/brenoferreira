-- 010 — Fase 3: eventos por bairro (gatilho por limiar), convites segmentados com RSVP e check-in,
-- empresários, funil de mantenedores, contribuições e clube de benefícios com carteirinha.

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------
create table public.event_thresholds (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  neighborhood_id uuid references public.neighborhoods(id),   -- null = padrão da unidade
  target integer not null default 2000,
  alert_50_at timestamptz,
  alert_80_at timestamptz,
  reached_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, neighborhood_id)
);
create trigger event_thresholds_set_updated_at before update on public.event_thresholds for each row execute function public.set_updated_at();

create table public.events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  name text not null,
  kind text not null default 'neighborhood' check (kind in ('neighborhood', 'business', 'supporter_pitch', 'training', 'other')),
  neighborhood_id uuid references public.neighborhoods(id),
  target_segment jsonb not null default '{}'::jsonb,          -- {neighborhood_ids, age_ranges, income_ranges, profile_segments, stages}
  starts_at timestamptz,
  location text,
  capacity integer,
  status text not null default 'draft' check (status in ('draft', 'planned', 'inviting', 'done', 'cancelled')),
  threshold_reached boolean not null default false,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index events_unit_status_idx on public.events (unit_id, status, starts_at);
create trigger events_set_updated_at before update on public.events for each row execute function public.set_updated_at();

create table public.event_invitations (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  event_id uuid not null references public.events(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  message_log_id uuid references public.message_log(id),
  sent_at timestamptz,
  rsvp text check (rsvp in ('yes', 'no', 'maybe')),
  rsvp_at timestamptz,
  checkin_code text unique,
  checked_in_at timestamptz,
  created_at timestamptz not null default now(),
  unique (event_id, person_id)
);
create index event_invitations_event_idx on public.event_invitations (event_id, rsvp);

-- pessoas cadastradas no próprio evento (origem)
alter table public.people add constraint people_source_event_fk foreign key (source_event_id) references public.events(id);

-- ---------------------------------------------------------------------------
-- Mantenedores, contribuições e benefícios
-- ---------------------------------------------------------------------------
create table public.supporter_eligibility_rules (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),                  -- null = global
  name text not null,
  condition jsonb not null,                                   -- {income_in:[...], profile_segment_in:[...], stage_in:[...], min_points:N, occupation_area_in:[...]}
  priority integer not null default 10,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.supporter_eligibility_rules (unit_id, name, condition, priority) values
  (null, 'Empresário ou autônomo', '{"profile_segment_in":["business"]}', 10),
  (null, 'Renda acima de 3 salários', '{"income_in":["over_3_mw"]}', 20),
  (null, 'Concluiu a jornada', '{"stage_in":["day16_done","church_connected"]}', 30)
on conflict do nothing;

create table public.supporters (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid references public.people(id) on delete set null,   -- null = mantenedor externo
  external_name text,
  external_phone_e164 text,
  external_email text,
  origin text not null default 'transtornar' check (origin in ('transtornar', 'external')),
  status text not null default 'prospect' check (status in ('prospect', 'invited', 'attended', 'active', 'paused', 'declined')),
  eligibility_rule_id uuid references public.supporter_eligibility_rules(id),
  contribution_plan text,
  monthly_amount numeric(10, 2),
  card_code text unique,
  since date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supporters_identity_chk check (person_id is not null or external_name is not null)
);
create unique index supporters_person_uidx on public.supporters (person_id) where person_id is not null;
create trigger supporters_set_updated_at before update on public.supporters for each row execute function public.set_updated_at();

create table public.contributions (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  supporter_id uuid not null references public.supporters(id) on delete cascade,
  amount numeric(10, 2) not null,
  paid_on date not null default current_date,
  method text not null default 'pix' check (method in ('pix', 'transfer', 'card', 'cash', 'other')),
  reference text,
  receipt_note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index contributions_supporter_idx on public.contributions (supporter_id, paid_on desc);

create table public.benefits (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  description text,
  rules text,
  valid_until date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger benefits_set_updated_at before update on public.benefits for each row execute function public.set_updated_at();

create table public.benefit_redemptions (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  benefit_id uuid not null references public.benefits(id) on delete cascade,
  supporter_id uuid not null references public.supporters(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  note text
);
create index benefit_redemptions_supporter_idx on public.benefit_redemptions (supporter_id, redeemed_at desc);

-- ---------------------------------------------------------------------------
-- Templates
-- ---------------------------------------------------------------------------
insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables) values
  (null, 'transtornar_evento_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   'Olá {{1}}! O Transtornar vai fazer um encontro: {{2}}, em {{3}}. Você vem? Para parar de receber convites, responda SAIR.',
   '[{"id":"rsvp_yes","title":"Eu vou"},{"id":"rsvp_maybe","title":"Talvez"},{"id":"rsvp_no","title":"Não posso"}]',
   '["first_name","event_name","event_details"]'),
  (null, 'transtornar_mantenedor_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   'Olá {{1}}! Queremos te apresentar como apoiar o Transtornar e os benefícios de quem investe no projeto: {{2}}. Para parar, responda SAIR.',
   '[{"id":"supporter_yes","title":"Quero saber"},{"id":"supporter_no","title":"Agora não"}]', '["first_name","details"]')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Gatilho de eventos por bairro
-- ---------------------------------------------------------------------------
create or replace function public.check_event_thresholds() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; v_total integer; v_pct numeric; v_event uuid; v_alerts integer := 0; v_events integer := 0; v_default integer;
begin
  perform public.assert_service_role();
  for r in
    select u.id as unit_id, n.id as neighborhood_id, n.name as neighborhood,
           coalesce(t.id, null) as threshold_id, coalesce(t.target, d.target, 2000) as target,
           t.alert_50_at, t.alert_80_at, t.reached_at
    from public.units u
    join public.unit_neighborhoods un on un.unit_id = u.id
    join public.neighborhoods n on n.id = un.neighborhood_id
    left join public.event_thresholds t on t.unit_id = u.id and t.neighborhood_id = n.id and t.active
    left join public.event_thresholds d on d.unit_id = u.id and d.neighborhood_id is null and d.active
    where u.active
  loop
    select coalesce(sum(x.total), 0) into v_total from (
      select count(*) as total from public.people p where p.unit_id = r.unit_id and p.neighborhood_id = r.neighborhood_id and p.review_status <> 'merged'
      union all
      select coalesce(sum(dt.count + dt.minor_count), 0) from public.decision_tally dt where dt.unit_id = r.unit_id and dt.neighborhood_id = r.neighborhood_id
    ) x;
    if v_total = 0 then continue; end if;
    v_pct := 100.0 * v_total / nullif(r.target, 0);
    if r.threshold_id is null and v_pct >= 50 then
      insert into public.event_thresholds (unit_id, neighborhood_id, target) values (r.unit_id, r.neighborhood_id, r.target)
      on conflict (unit_id, neighborhood_id) do nothing;
    end if;
    if v_pct >= 50 and r.alert_50_at is null then
      update public.event_thresholds set alert_50_at = now() where unit_id = r.unit_id and neighborhood_id = r.neighborhood_id;
      insert into public.notifications (unit_id, recipient_profile_id, kind, title, ref_table, ref_id)
      select r.unit_id, pr.id, 'event_threshold', r.neighborhood || ': ' || v_total || ' decisões (50% da meta de ' || r.target || ')', 'neighborhoods', r.neighborhood_id
      from public.profiles pr where pr.unit_id = r.unit_id and pr.active and pr.role in ('central', 'unit_admin');
      v_alerts := v_alerts + 1;
    end if;
    if v_pct >= 80 and r.alert_80_at is null then
      update public.event_thresholds set alert_80_at = now() where unit_id = r.unit_id and neighborhood_id = r.neighborhood_id;
      insert into public.notifications (unit_id, recipient_profile_id, kind, title, ref_table, ref_id)
      select r.unit_id, pr.id, 'event_threshold', r.neighborhood || ': ' || v_total || ' decisões (80% da meta)', 'neighborhoods', r.neighborhood_id
      from public.profiles pr where pr.unit_id = r.unit_id and pr.active and pr.role in ('central', 'unit_admin');
      v_alerts := v_alerts + 1;
    end if;
    if v_pct >= 100 and r.reached_at is null then
      update public.event_thresholds set reached_at = now() where unit_id = r.unit_id and neighborhood_id = r.neighborhood_id;
      insert into public.events (unit_id, name, kind, neighborhood_id, target_segment, status, threshold_reached, notes)
      values (r.unit_id, 'Evento Transtornar no ' || r.neighborhood, 'neighborhood', r.neighborhood_id,
              jsonb_build_object('neighborhood_ids', jsonb_build_array(r.neighborhood_id)), 'draft', true,
              'Criado automaticamente: ' || v_total || ' decisões no bairro (meta ' || r.target || ').')
      returning id into v_event;
      insert into public.notifications (unit_id, recipient_profile_id, kind, title, ref_table, ref_id)
      select r.unit_id, pr.id, 'event_created', 'Meta atingida no ' || r.neighborhood || ' — evento em rascunho', 'events', v_event
      from public.profiles pr where pr.unit_id = r.unit_id and pr.active and pr.role in ('central', 'unit_admin');
      v_events := v_events + 1;
    end if;
  end loop;
  return jsonb_build_object('alerts', v_alerts, 'events_created', v_events);
end $$;

-- Público-alvo de um evento (segmentação configurável)
create or replace function public.event_audience(p_event_id uuid) returns setof public.people
language plpgsql stable security definer set search_path = public as $$
declare e record; seg jsonb;
begin
  select * into e from public.events where id = p_event_id;
  if e.id is null then return; end if;
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

-- Dispara convites: só para quem consentiu marketing_events; respeita quiet hours e capacidade
create or replace function public.invite_to_event(p_event_id uuid, p_limit integer default 1000) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e record; p record; v_msg uuid; v_code text; v_sent integer := 0; v_skipped integer := 0; v_details text; v_first text; v_phone text;
begin
  select * into e from public.events where id = p_event_id;
  if e.id is null then raise exception 'event_not_found'; end if;
  perform public.assert_staff_or_team(e.unit_id, array['central']);
  v_details := concat_ws(' · ', to_char(e.starts_at at time zone (select timezone from public.units where id = e.unit_id), 'DD/MM às HH24hMI'), e.location);
  for p in select * from public.event_audience(p_event_id) limit greatest(1, p_limit) loop
    select pc.phone_e164, split_part(pc.full_name, ' ', 1) into v_phone, v_first from public.people_contacts pc where pc.person_id = p.id;
    if v_phone is null then v_skipped := v_skipped + 1; continue; end if;
    if not exists (select 1 from public.consents c where c.person_id = p.id and c.purpose = 'marketing_events' and c.granted and c.revoked_at is null)
       or not exists (select 1 from public.consents c where c.person_id = p.id and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null) then
      v_skipped := v_skipped + 1; continue;
    end if;
    if exists (select 1 from public.event_invitations i where i.event_id = p_event_id and i.person_id = p.id) then v_skipped := v_skipped + 1; continue; end if;
    v_code := upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
    insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, status, scheduled_for, payload)
    values (e.unit_id, p.id, v_phone, 'template', 'transtornar_evento_v1', 'queued', public.next_send_slot(e.unit_id, now()),
            jsonb_build_object('first_name', v_first, 'body_params', jsonb_build_array(v_first, e.name, v_details), 'event_id', e.id))
    returning id into v_msg;
    insert into public.event_invitations (unit_id, event_id, person_id, message_log_id, sent_at, checkin_code)
    values (e.unit_id, p_event_id, p.id, v_msg, now(), v_code);
    insert into public.person_events (unit_id, person_id, event_type, payload) values (e.unit_id, p.id, 'event_invited', jsonb_build_object('event', e.name));
    v_sent := v_sent + 1;
  end loop;
  update public.events set status = 'inviting' where id = p_event_id and status in ('draft', 'planned');
  return jsonb_build_object('invited', v_sent, 'skipped', v_skipped);
end $$;

create or replace function public.event_rsvp(p_unit_id uuid, p_person_id uuid, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
declare i record;
begin
  select inv.* into i from public.event_invitations inv join public.events e on e.id = inv.event_id
  where inv.person_id = p_person_id and inv.unit_id = p_unit_id and e.status in ('inviting', 'planned') and inv.rsvp is null
  order by inv.sent_at desc limit 1;
  if i.id is null then return; end if;
  update public.event_invitations set rsvp = p_answer, rsvp_at = now() where id = i.id;
  insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, p_person_id, 'event_rsvp', jsonb_build_object('event_id', i.event_id, 'rsvp', p_answer));
  if p_answer = 'yes' then
    insert into public.message_log (unit_id, person_id, to_phone_e164, kind, status, scheduled_for, payload)
    select p_unit_id, p_person_id, pc.phone_e164, 'text', 'queued', now(),
           jsonb_build_object('text', 'Que bom! Seu código de entrada é ' || i.checkin_code || '. Te esperamos!')
    from public.people_contacts pc where pc.person_id = p_person_id;
  end if;
end $$;

create or replace function public.event_checkin(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i record;
begin
  select inv.*, e.name as event_name into i from public.event_invitations inv join public.events e on e.id = inv.event_id where inv.checkin_code = upper(p_code);
  if i.id is null then raise exception 'invite_not_found'; end if;
  perform public.assert_staff_or_team(i.unit_id, array['central', 'follow_up']);
  if i.checked_in_at is not null then return jsonb_build_object('already', true, 'person_id', i.person_id, 'event', i.event_name); end if;
  update public.event_invitations set checked_in_at = now(), rsvp = coalesce(rsvp, 'yes') where id = i.id;
  insert into public.person_events (unit_id, person_id, event_type, payload) values (i.unit_id, i.person_id, 'event_checkin', jsonb_build_object('event_id', i.event_id));
  perform public.add_points(i.person_id, 'event_checkin', i.event_id);
  return jsonb_build_object('already', false, 'person_id', i.person_id, 'event', i.event_name,
                            'name', (select full_name from public.people_contacts where person_id = i.person_id));
end $$;

-- ---------------------------------------------------------------------------
-- Mantenedores
-- ---------------------------------------------------------------------------
create or replace function public.supporter_candidates(p_unit_id uuid) returns table (person_id uuid, full_name text, rule_id uuid, rule_name text)
language sql stable security definer set search_path = public as $$
  select distinct on (p.id) p.id, pc.full_name, r.id, r.name
  from public.people p
  join public.people_contacts pc on pc.person_id = p.id
  join public.supporter_eligibility_rules r on r.active
    and r.unit_id is not distinct from (case when exists (select 1 from public.supporter_eligibility_rules x where x.unit_id = p_unit_id and x.active) then p_unit_id else null end)
  where p.unit_id = p_unit_id
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

create or replace function public.create_supporter(p_person_id uuid default null, p_status text default 'prospect', p_external jsonb default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_id uuid; v_rule uuid; v_code text;
begin
  if p_person_id is not null then
    select unit_id into v_unit from public.people where id = p_person_id;
  else
    v_unit := public.auth_unit_id();
  end if;
  perform public.assert_staff_or_team(v_unit, array['central']);
  if p_person_id is not null then select rule_id into v_rule from public.supporter_candidates(v_unit) where person_id = p_person_id limit 1; end if;
  v_code := upper(substr(encode(extensions.gen_random_bytes(5), 'hex'), 1, 8));
  insert into public.supporters (unit_id, person_id, external_name, external_phone_e164, external_email, origin, status, eligibility_rule_id, card_code, since)
  values (v_unit, p_person_id, p_external->>'name', case when p_external ? 'phone' then public.normalize_e164(p_external->>'phone') end, p_external->>'email',
          case when p_person_id is null then 'external' else 'transtornar' end, p_status, v_rule, v_code,
          case when p_status = 'active' then current_date end)
  on conflict (person_id) where person_id is not null do update set status = excluded.status returning id into v_id;
  if p_person_id is not null and p_status = 'active' then
    update public.people set stage = 'supporter' where id = p_person_id and stage not in ('anonymized', 'opted_out');
  end if;
  return v_id;
end $$;

create or replace function public.supporter_transition(p_supporter_id uuid, p_to text, p_plan text default null, p_amount numeric default null) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select * into s from public.supporters where id = p_supporter_id;
  if s.id is null then raise exception 'supporter_not_found'; end if;
  perform public.assert_staff_or_team(s.unit_id, array['central']);
  update public.supporters set status = p_to, contribution_plan = coalesce(p_plan, contribution_plan), monthly_amount = coalesce(p_amount, monthly_amount),
    since = case when p_to = 'active' then coalesce(since, current_date) else since end
  where id = p_supporter_id;
  if p_to = 'active' and s.person_id is not null then
    update public.people set stage = 'supporter' where id = s.person_id and stage not in ('anonymized', 'opted_out');
    insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via, collected_by)
    select s.unit_id, s.person_id, 'benefits_club', true, p.consent_text_version, 'admin', auth.uid() from public.people p where p.id = s.person_id
    on conflict do nothing;
  end if;
end $$;

create or replace function public.redeem_benefit(p_card_code text, p_benefit_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s record; b record; v_id uuid;
begin
  select * into s from public.supporters where card_code = upper(p_card_code);
  if s.id is null then raise exception 'supporter_not_found'; end if;
  perform public.assert_staff_or_team(s.unit_id, array['central']);
  if s.status <> 'active' then raise exception 'supporter_not_active'; end if;
  select * into b from public.benefits where id = p_benefit_id and unit_id = s.unit_id and active and (valid_until is null or valid_until >= current_date);
  if b.id is null then raise exception 'benefit_not_available'; end if;
  insert into public.benefit_redemptions (unit_id, benefit_id, supporter_id, note) values (s.unit_id, p_benefit_id, s.id, p_note) returning id into v_id;
  return jsonb_build_object('id', v_id, 'benefit', b.title);
end $$;

-- Carteirinha pública (só primeiro nome e validade; sem PII adicional)
create or replace function public.supporter_card(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'name', coalesce(split_part(pc.full_name, ' ', 1), split_part(s.external_name, ' ', 1)),
    'unit', u.name,
    'status', s.status,
    'since', s.since,
    'code', s.card_code,
    'benefits', (select coalesce(jsonb_agg(jsonb_build_object('title', b.title, 'partner', c.name, 'rules', b.rules) order by b.title), '[]')
                 from public.benefits b join public.companies c on c.id = b.company_id
                 where b.unit_id = s.unit_id and b.active and (b.valid_until is null or b.valid_until >= current_date)))
  from public.supporters s
  join public.units u on u.id = s.unit_id
  left join public.people_contacts pc on pc.person_id = s.person_id
  where s.card_code = upper(p_code) and s.status = 'active'
$$;

-- ---------------------------------------------------------------------------
-- Botões do WhatsApp: RSVP e interesse em ser mantenedor
-- ---------------------------------------------------------------------------
create or replace function public.handle_button(p_unit_id uuid, p_person_id uuid, p_phone_e164 text, p_button text, p_wamid text) returns text
language plpgsql security definer set search_path = public as $$
declare v_stage text; v_team uuid;
begin
  select stage into v_stage from public.people where id = p_person_id;
  if p_button = 'optin_yes' then
    perform public.confirm_optin(p_unit_id, p_person_id, p_wamid);
    perform public.enqueue_video1(p_unit_id, p_person_id);
    return 'optin_confirmed_video_queued';
  elsif p_button = 'video_watched' then
    if v_stage in ('registered', 'first_contact_pending', 'paused', 'inactive') then perform public.confirm_optin(p_unit_id, p_person_id, p_wamid); end if;
    insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, p_person_id, 'video_watched', jsonb_build_object('wamid', p_wamid));
    perform public.journey_mark_watched(p_person_id, p_wamid);
    return 'video_watched';
  elsif p_button like 'fb\_%' then
    perform public.journey_feedback(p_person_id, right(p_button, 1)::smallint);
    return 'feedback';
  elsif p_button like 'income\_%' then
    perform public.journey_answer(p_person_id, 'income', substr(p_button, 8));
    return 'profile_answer';
  elsif p_button in ('events_yes', 'events_no') then
    perform public.journey_answer(p_person_id, 'events_optin', substr(p_button, 8));
    return 'profile_answer';
  elsif p_button in ('church_yes', 'church_have', 'church_no') then
    perform public.journey_answer(p_person_id, 'church', substr(p_button, 8));
    return 'profile_answer';
  elsif p_button like 'rsvp\_%' then
    perform public.event_rsvp(p_unit_id, p_person_id, substr(p_button, 6));
    return 'event_rsvp';
  elsif p_button in ('supporter_yes', 'supporter_no') then
    if p_button = 'supporter_yes' then
      select t.id into v_team from public.teams t where t.unit_id = p_unit_id and t.kind = 'central';
      insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority)
      select p_unit_id, p_person_id, v_team, 'other', 'quer conhecer o modelo de mantenedor', 2
      where not exists (select 1 from public.referrals r where r.person_id = p_person_id and r.referral_type = 'other' and r.reason like 'quer conhecer o modelo%' and r.status not in ('done', 'cancelled'));
      insert into public.supporters (unit_id, person_id, origin, status, card_code)
      values (p_unit_id, p_person_id, 'transtornar', 'invited', upper(substr(encode(extensions.gen_random_bytes(5), 'hex'), 1, 8)))
      on conflict (person_id) where person_id is not null do update set status = case when public.supporters.status = 'prospect' then 'invited' else public.supporters.status end;
    end if;
    return 'supporter_interest';
  elsif p_button = 'optin_no' then
    update public.people set stage = 'paused' where id = p_person_id and stage in ('registered', 'first_contact_pending');
    update public.message_log set status = 'skipped', skip_reason = 'paused' where person_id = p_person_id and status = 'queued';
    update public.person_journeys set status = 'paused', next_send_at = null where person_id = p_person_id;
    return 'paused';
  elsif p_button = 'stop' then
    perform public.opt_out_person(p_unit_id, p_phone_e164, 'botão Parar');
    return 'opted_out';
  end if;
  return 'unknown_button';
end $$;

-- ---------------------------------------------------------------------------
-- Impacto com as métricas da Fase 3
-- ---------------------------------------------------------------------------
drop materialized view if exists public.mv_impact cascade;
create materialized view public.mv_impact as
  select u.id as unit_id, u.name as unit_name,
    (select count(*) from public.people p where p.unit_id = u.id and p.review_status <> 'merged') as people_registered,
    (select coalesce(sum(count + minor_count), 0) from public.decision_tally t where t.unit_id = u.id) as decisions_without_record,
    (select count(*) from public.people p where p.unit_id = u.id and p.stage in ('journey_active', 'day7_done', 'day16_done', 'church_connected', 'supporter')) as journey_active,
    (select count(*) from public.reward_grants g join public.reward_rules r on r.id = g.rule_id where g.unit_id = u.id and r.key = 'day7') as reached_day7,
    (select count(*) from public.reward_grants g join public.reward_rules r on r.id = g.rule_id where g.unit_id = u.id and r.key = 'day16') as reached_day16,
    (select count(*) from public.church_connections c where c.unit_id = u.id and c.status = 'connected') as church_connected,
    (select count(*) from public.assistance_programs ap where ap.unit_id = u.id) as families_in_food_program,
    (select count(*) from public.delivery_orders d where d.unit_id = u.id and d.status = 'delivered' and d.kind = 'basic_food') as food_baskets_delivered,
    (select count(*) from public.delivery_orders d where d.unit_id = u.id and d.status = 'delivered' and d.kind = 'home_item') as home_items_delivered,
    (select count(*) from public.enrollments e where e.unit_id = u.id and e.status = 'completed') as courses_completed,
    (select count(*) from public.job_placements jp where jp.unit_id = u.id and jp.status = 'hired') as people_hired,
    (select count(distinct p.neighborhood_id) from public.people p where p.unit_id = u.id) as neighborhoods_reached,
    (select count(*) from public.events e where e.unit_id = u.id and e.status = 'done') as events_done,
    (select count(*) from public.event_invitations i join public.events e on e.id = i.event_id where i.unit_id = u.id and i.checked_in_at is not null) as event_checkins,
    (select count(*) from public.supporters s where s.unit_id = u.id and s.status = 'active') as active_supporters,
    (select coalesce(sum(c.amount), 0) from public.contributions c where c.unit_id = u.id and c.paid_on > current_date - 365) as contributions_12m,
    (select count(*) from public.benefit_redemptions br where br.unit_id = u.id) as benefit_redemptions,
    now() as refreshed_at
  from public.units u;
create unique index mv_impact_unit_idx on public.mv_impact (unit_id);
create or replace view public.v_impact_by_unit with (security_invoker = true) as
  select m.* from public.mv_impact m where public.can_read_unit(m.unit_id);
grant select on public.mv_impact to authenticated;

create or replace view public.v_supporter_funnel with (security_invoker = true) as
  select unit_id, status, count(*) as total, coalesce(sum(monthly_amount), 0) as monthly_amount
  from public.supporters group by unit_id, status;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('event-thresholds', '0 5 * * *', $c$ select public.check_event_thresholds() $c$);
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.events, public.event_invitations;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Grants e RLS
-- ---------------------------------------------------------------------------
grant execute on function public.invite_to_event(uuid, integer), public.event_audience(uuid), public.event_checkin(text),
  public.supporter_candidates(uuid), public.create_supporter(uuid, text, jsonb), public.supporter_transition(uuid, text, text, numeric),
  public.redeem_benefit(text, uuid, text) to authenticated;
grant execute on function public.supporter_card(text) to anon, authenticated;
grant execute on all functions in schema public to service_role;

alter table public.event_thresholds enable row level security;
alter table public.events enable row level security;
alter table public.event_invitations enable row level security;
alter table public.supporter_eligibility_rules enable row level security;
alter table public.supporters enable row level security;
alter table public.contributions enable row level security;
alter table public.benefits enable row level security;
alter table public.benefit_redemptions enable row level security;

create policy event_thresholds_select on public.event_thresholds for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy event_thresholds_write on public.event_thresholds for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy events_select on public.events for select to authenticated using (public.can_read_unit(unit_id));
create policy events_write on public.events for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy event_invitations_select on public.event_invitations for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy supporter_rules_select on public.supporter_eligibility_rules for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy supporter_rules_write on public.supporter_eligibility_rules for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy supporters_select on public.supporters for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy supporters_write on public.supporters for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy contributions_select on public.contributions for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy contributions_write on public.contributions for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy benefits_select on public.benefits for select to authenticated using (public.can_read_unit(unit_id));
create policy benefits_write on public.benefits for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy benefit_redemptions_select on public.benefit_redemptions for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));

-- ---------------------------------------------------------------------------
-- RPCs de escrita usadas pelo painel (preenchem unit_id a partir do perfil)
-- ---------------------------------------------------------------------------
create or replace function public.create_event(p_name text, p_kind text default 'neighborhood', p_neighborhood_id uuid default null, p_target_segment jsonb default '{}'::jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id(); v_id uuid;
begin
  perform public.assert_role('central', 'unit_admin');
  if p_neighborhood_id is not null and not exists (select 1 from public.unit_neighborhoods un where un.unit_id = v_unit and un.neighborhood_id = p_neighborhood_id) then
    raise exception 'neighborhood_not_in_unit';
  end if;
  insert into public.events (unit_id, name, kind, neighborhood_id, target_segment, status, created_by)
  values (v_unit, p_name, p_kind, p_neighborhood_id, coalesce(p_target_segment, '{}'::jsonb), 'planned', auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.record_contribution(p_supporter_id uuid, p_amount numeric, p_method text default 'pix', p_reference text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare s record; v_id uuid;
begin
  select * into s from public.supporters where id = p_supporter_id;
  if s.id is null then raise exception 'supporter_not_found'; end if;
  perform public.assert_staff_or_team(s.unit_id, array['central']);
  if p_amount <= 0 then raise exception 'invalid_amount'; end if;
  insert into public.contributions (unit_id, supporter_id, amount, method, reference, created_by)
  values (s.unit_id, p_supporter_id, p_amount, p_method, p_reference, auth.uid()) returning id into v_id;
  return v_id;
end $$;

grant execute on function public.create_event(text, text, uuid, jsonb), public.record_contribution(uuid, numeric, text, text) to authenticated;
