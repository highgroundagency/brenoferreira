-- 006 — auditoria, RPCs (security definer), views agregadas, jobs e RLS em todas as tabelas
-- Toda RPC valida o papel (assert_role) — exceções: get_invite (anon) e accept_invite (authenticated sem perfil).
-- As RPCs chamadas pelas Edge Functions exigem service_role.

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),
  actor_id uuid,
  actor_role text,
  action text not null,
  table_name text,
  row_id uuid,
  diff jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_row_idx on public.audit_log (table_name, row_id, created_at desc);
create trigger audit_log_append_only before update or delete on public.audit_log for each row execute function public.reject_change();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.assert_role(variadic p_roles text[]) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if public.auth_role() is null or not (public.auth_role() = any (p_roles)) then
    raise insufficient_privilege using message = 'papel não autorizado para esta operação';
  end if;
end $$;

create or replace function public.assert_service_role() returns void
language plpgsql stable as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    raise insufficient_privilege using message = 'somente service_role';
  end if;
end $$;

create or replace function public.normalize_e164(p text) returns text
language plpgsql immutable strict as $$
declare d text := regexp_replace(p, '\D', '', 'g');
begin
  if length(d) in (10, 11) then return '+55' || d; end if;     -- DDD + número (BR)
  if d like '55%' and length(d) in (12, 13) then return '+' || d; end if;
  return '+' || d;
end $$;

-- Variantes BR com e sem o 9º dígito (a Meta pode devolver wa_id sem o 9)
create or replace function public.phone_variants(p text) returns text[]
language sql immutable strict as $$
  select case
    when p ~ '^\+55\d{2}9?\d{8}$' then array['+55' || substr(regexp_replace(p, '^\+55', ''), 1, 2) || '9' || right(p, 8),
                                            '+55' || substr(regexp_replace(p, '^\+55', ''), 1, 2) || right(p, 8)]
    else array[p] end
$$;

create or replace function public.address_hash(p_street text, p_number text, p_complement text, p_postal_code text) returns text
language sql immutable as $$
  select encode(sha256(convert_to(public.normalize_text(concat_ws('|', coalesce(p_street, ''), coalesce(p_number, ''), coalesce(p_complement, ''), regexp_replace(coalesce(p_postal_code, ''), '\D', '', 'g'))), 'UTF8')), 'hex')
$$;

-- Próximo horário permitido (fora das quiet hours da unidade)
create or replace function public.next_send_slot(p_unit_id uuid, p_at timestamptz) returns timestamptz
language plpgsql stable as $$
declare
  u record; qs time; qe time; lt timestamp; candidate timestamp;
begin
  select timezone, settings into u from public.units where id = p_unit_id;
  qs := coalesce((u.settings->'quiet_hours'->>'start')::time, '21:00');
  qe := coalesce((u.settings->'quiet_hours'->>'end')::time, '08:00');
  lt := p_at at time zone u.timezone;
  if qs > qe then                                   -- cruza a meia-noite (21:00 -> 08:00)
    if lt::time >= qs then candidate := (lt::date + 1) + qe;
    elsif lt::time < qe then candidate := lt::date + qe;
    else return p_at; end if;
  else
    if lt::time >= qs and lt::time < qe then candidate := lt::date + qe; else return p_at; end if;
  end if;
  return candidate at time zone u.timezone;
end $$;

create or replace function public.first_contact_template(p_unit_id uuid, p_phone_owner text) returns text
language sql stable as $$
  select case when u.settings->>'first_contact_mode' = 'video_first' and p_phone_owner = 'self'
              then 'transtornar_video1_v1' else 'transtornar_optin_v1' end
  from public.units u where u.id = p_unit_id
$$;

create or replace function public.enqueue_first_contact(p_person_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  p record; v_template text; v_id uuid; v_delay int;
begin
  select pe.id, pe.unit_id, pc.phone_e164, pc.phone_owner, pc.full_name, pc.contact_name, u.settings
    into p
  from public.people pe join public.people_contacts pc on pc.person_id = pe.id join public.units u on u.id = pe.unit_id
  where pe.id = p_person_id;
  if not found then return null; end if;
  if not exists (select 1 from public.consents c where c.person_id = p.id and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null) then
    return null;
  end if;
  v_template := public.first_contact_template(p.unit_id, p.phone_owner);
  v_delay := coalesce((p.settings->>'first_contact_delay_minutes')::int, 10);
  insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, status, scheduled_for, payload)
  values (p.unit_id, p.id, p.phone_e164, 'template', v_template, 'queued',
          public.next_send_slot(p.unit_id, now() + make_interval(mins => v_delay)),
          jsonb_build_object('first_name', split_part(coalesce(nullif(p.contact_name, ''), p.full_name), ' ', 1), 'mode',
                             case when v_template = 'transtornar_video1_v1' then 'video_first' else 'optin_first' end))
  returning id into v_id;
  update public.people set stage = 'first_contact_pending' where id = p.id and stage = 'registered';
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- register_person: transação única, idempotente por client_uuid, roteamento e 1º contato
-- ---------------------------------------------------------------------------
create or replace function public.register_person(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_unit uuid; v_actor uuid; v_person uuid; v_existing uuid; v_household uuid; v_city uuid; v_nbh uuid;
  v_phone text; v_review text := 'ok'; v_dup uuid; v_kind text; v_hash text; v_msg uuid; v_has_need boolean := false;
  v_consent_version text; n jsonb; c text; v_phone_owner text;
begin
  perform public.assert_role('evangelist', 'central', 'unit_admin');
  v_unit := public.auth_unit_id(); v_actor := auth.uid();
  if v_unit is null then raise exception 'sem unidade'; end if;

  select id into v_existing from public.people where client_uuid = (payload->>'client_uuid')::uuid;
  if found then
    return jsonb_build_object('person_id', v_existing, 'idempotent', true);
  end if;

  if not coalesce((payload->>'is_adult')::boolean, false) then
    raise exception 'minor_not_allowed' using hint = 'use record_decision_tally(neighborhood_id, true)';
  end if;
  if not coalesce((payload->'consent'->>'accepted')::boolean, false) then
    raise exception 'consent_required';
  end if;
  v_consent_version := coalesce(payload->'consent'->>'version', 'v1');
  v_nbh := (payload->>'neighborhood_id')::uuid;
  select n.city_id into v_city from public.neighborhoods n
  join public.unit_neighborhoods un on un.neighborhood_id = n.id and un.unit_id = v_unit
  where n.id = v_nbh;
  if v_city is null then raise exception 'neighborhood_not_in_unit'; end if;
  v_phone := public.normalize_e164(payload->>'phone');
  if v_phone !~ '^\+\d{10,15}$' then raise exception 'invalid_phone'; end if;
  v_phone_owner := coalesce(payload->>'phone_owner', 'self');
  v_kind := coalesce(payload->>'address_kind', 'fixed');

  perform set_config('app.skip_routing', 'on', true);

  if v_kind in ('fixed', 'no_number') and (coalesce(payload->>'street', '') <> '' or coalesce(payload->>'postal_code', '') <> '') then
    v_hash := public.address_hash(payload->>'street', payload->>'number', payload->>'complement', payload->>'postal_code');
    insert into public.households (unit_id, address_hash, neighborhood_id, city_id)
    values (v_unit, v_hash, v_nbh, v_city)
    on conflict (unit_id, address_hash) do update set updated_at = now()
    returning id into v_household;
  end if;

  insert into public.people (unit_id, client_uuid, household_id, neighborhood_id, city_id, age_range, has_basic_need, children_count,
                             needs_job, occupation_area, wants_training, attends_church, decided_at, source, registered_by, observation, consent_text_version)
  values (v_unit, (payload->>'client_uuid')::uuid, v_household, v_nbh, v_city, nullif(payload->>'age_range', ''),
          jsonb_array_length(coalesce(payload->'needs', '[]'::jsonb)) > 0,
          coalesce(jsonb_array_length(coalesce(payload->'children', '[]'::jsonb)), 0),
          (payload->>'needs_job')::boolean, nullif(payload->>'occupation_area', ''), (payload->>'wants_training')::boolean,
          (payload->>'attends_church')::boolean, coalesce((payload->>'decided_at')::timestamptz, now()),
          coalesce(nullif(payload->>'source', ''), 'street'), v_actor, left(nullif(payload->>'observation', ''), 140), v_consent_version)
  returning id into v_person;

  begin
    insert into public.people_contacts (person_id, unit_id, full_name, phone_e164, phone_owner, contact_name, is_primary, email, address_kind,
                                        street, number, complement, postal_code, address_raw)
    values (v_person, v_unit, payload->>'full_name', v_phone, v_phone_owner, nullif(payload->>'contact_name', ''), true,
            nullif(payload->>'email', ''), v_kind, nullif(payload->>'street', ''), nullif(payload->>'number', ''),
            nullif(payload->>'complement', ''), nullif(payload->>'postal_code', ''), nullif(payload->>'address_raw', ''));
  exception when unique_violation then
    select pc.person_id into v_dup from public.people_contacts pc where pc.unit_id = v_unit and pc.phone_e164 = v_phone and pc.is_primary;
    insert into public.people_contacts (person_id, unit_id, full_name, phone_e164, phone_owner, contact_name, is_primary, email, address_kind,
                                        street, number, complement, postal_code, address_raw)
    values (v_person, v_unit, payload->>'full_name', v_phone, v_phone_owner, nullif(payload->>'contact_name', ''), false,
            nullif(payload->>'email', ''), v_kind, nullif(payload->>'street', ''), nullif(payload->>'number', ''),
            nullif(payload->>'complement', ''), nullif(payload->>'postal_code', ''), nullif(payload->>'address_raw', ''));
    v_review := 'possible_duplicate';
    update public.people set review_status = 'possible_duplicate', duplicate_of_person_id = v_dup where id = v_person;
  end;

  for c in select jsonb_array_elements_text(coalesce(payload->'children', '[]'::jsonb)) loop
    insert into public.children (unit_id, person_id, age_band) values (v_unit, v_person, c);
  end loop;

  for n in select * from jsonb_array_elements(coalesce(payload->'needs', '[]'::jsonb)) loop
    v_has_need := true;
    insert into public.needs (unit_id, person_id, household_id, need_type, item_code, raw_text)
    values (v_unit, v_person, v_household, n->>'need_type', nullif(n->>'item_code', ''), nullif(n->>'raw_text', ''));
  end loop;

  insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via, collected_by)
  values (v_unit, v_person, 'spiritual_followup', true, v_consent_version, 'evangelist_app', v_actor),
         (v_unit, v_person, 'whatsapp_contact', true, v_consent_version, 'evangelist_app', v_actor);
  if v_has_need then
    insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via, collected_by)
    values (v_unit, v_person, 'social_assistance', true, v_consent_version, 'evangelist_app', v_actor);
  end if;

  if v_household is not null then
    update public.households h set children_count = (select count(*) from public.children ch join public.people pe on pe.id = ch.person_id where pe.household_id = h.id)
    where h.id = v_household;
  end if;

  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload)
  values (v_unit, v_person, 'registered', v_actor, jsonb_build_object('review_status', v_review, 'source', coalesce(nullif(payload->>'source', ''), 'street')));

  perform public.apply_routing_rules(v_person);

  if v_review = 'ok' then
    v_msg := public.enqueue_first_contact(v_person);
  end if;

  return jsonb_build_object('person_id', v_person, 'idempotent', false, 'review_status', v_review, 'household_id', v_household,
                            'first_contact', (select template_name from public.message_log where id = v_msg));
end $$;

create or replace function public.record_decision_tally(p_neighborhood_id uuid, p_minor boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id();
begin
  perform public.assert_role('evangelist', 'central', 'unit_admin');
  insert into public.decision_tally (unit_id, neighborhood_id, registered_by, decided_on, count, minor_count)
  values (v_unit, p_neighborhood_id, auth.uid(), current_date, case when p_minor then 0 else 1 end, case when p_minor then 1 else 0 end)
  on conflict (unit_id, neighborhood_id, registered_by, decided_on) do update
    set count = public.decision_tally.count + excluded.count, minor_count = public.decision_tally.minor_count + excluded.minor_count;
end $$;

-- ---------------------------------------------------------------------------
-- Filas e ficha
-- ---------------------------------------------------------------------------
create or replace function public.referral_transition(p_referral_id uuid, p_to text, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_allowed boolean;
begin
  select * into r from public.referrals where id = p_referral_id;
  if not found then raise exception 'referral_not_found'; end if;
  v_allowed := public.can_write_unit(r.unit_id) or (public.auth_role() = 'team_member' and r.team_id = any (public.auth_team_ids()));
  if not v_allowed then raise insufficient_privilege; end if;
  if not (
    (r.status = 'new' and p_to in ('triaged', 'in_progress', 'cancelled')) or
    (r.status = 'triaged' and p_to in ('in_progress', 'waiting', 'done', 'cancelled')) or
    (r.status = 'in_progress' and p_to in ('waiting', 'done', 'cancelled')) or
    (r.status = 'waiting' and p_to in ('in_progress', 'done', 'cancelled'))) then
    raise exception 'invalid_transition % -> %', r.status, p_to;
  end if;
  update public.referrals set
    status = p_to,
    first_response_at = coalesce(first_response_at, now()),
    assigned_to = coalesce(assigned_to, case when p_to = 'in_progress' then auth.uid() end),
    assigned_at = coalesce(assigned_at, case when p_to = 'in_progress' then now() end),
    done_at = case when p_to = 'done' then now() else done_at end,
    cancelled_reason = case when p_to = 'cancelled' then coalesce(p_note, cancelled_reason) else cancelled_reason end
  where id = p_referral_id;
  insert into public.referral_events (unit_id, referral_id, from_status, to_status, actor_profile_id, note)
  values (r.unit_id, r.id, r.status, p_to, auth.uid(), p_note);
  if p_to = 'done' and r.need_id is not null then
    update public.needs set status = 'fulfilled' where id = r.need_id and status in ('open', 'routed', 'in_assistance');
  end if;
end $$;

create or replace function public.mark_duplicate(p_person_id uuid, p_duplicate_of uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  if v_unit is null or not public.can_write_unit(v_unit) then raise insufficient_privilege; end if;
  update public.people set review_status = 'merged', duplicate_of_person_id = p_duplicate_of, stage = 'inactive' where id = p_person_id;
  update public.referrals set status = 'cancelled', cancelled_reason = 'duplicate' where person_id = p_person_id and status not in ('done', 'cancelled');
  update public.message_log set status = 'skipped', skip_reason = 'duplicate' where person_id = p_person_id and status = 'queued';
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload)
  values (v_unit, p_person_id, 'duplicate_marked', auth.uid(), jsonb_build_object('duplicate_of', p_duplicate_of));
end $$;

-- "Mesma casa, pessoa diferente": libera a pessoa que compartilha o telefone e envia o opt-in a quem atende
create or replace function public.confirm_distinct_person(p_person_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_msg uuid;
begin
  select unit_id into v_unit from public.people where id = p_person_id and review_status = 'possible_duplicate';
  if v_unit is null or not public.can_write_unit(v_unit) then raise insufficient_privilege; end if;
  update public.people set review_status = 'ok', duplicate_of_person_id = null where id = p_person_id;
  update public.people_contacts set phone_owner = case when phone_owner = 'self' then 'family' else phone_owner end where person_id = p_person_id;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id) values (v_unit, p_person_id, 'distinct_confirmed', auth.uid());
  perform public.apply_routing_rules(p_person_id);
  v_msg := public.enqueue_first_contact(p_person_id);
  return v_msg;
end $$;

create or replace function public.open_person_record(p_person_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; result jsonb;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  if v_unit is null or not (public.can_read_unit(v_unit) and public.is_unit_staff()) then raise insufficient_privilege; end if;
  insert into public.audit_log (unit_id, actor_id, actor_role, action, table_name, row_id)
  values (v_unit, auth.uid(), public.auth_role(), 'open_person_record', 'people', p_person_id);
  select jsonb_build_object(
    'person', to_jsonb(pe) - 'observation' || jsonb_build_object('observation', case when public.auth_role() in ('central', 'unit_admin') then pe.observation end),
    'contact', (select to_jsonb(pc) from public.people_contacts pc where pc.person_id = pe.id),
    'neighborhood', (select nb.name from public.neighborhoods nb where nb.id = pe.neighborhood_id),
    'children', (select coalesce(jsonb_agg(to_jsonb(c) order by c.age_band), '[]') from public.children c where c.person_id = pe.id),
    'needs', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at), '[]') from public.needs n where n.person_id = pe.id),
    'consents', (select coalesce(jsonb_agg(to_jsonb(co) order by co.granted_at), '[]') from public.consents co where co.person_id = pe.id),
    'referrals', (select coalesce(jsonb_agg((to_jsonb(r) || jsonb_build_object('team_kind', t.kind, 'team_name', t.name)) order by r.created_at), '[]')
                  from public.referrals r join public.teams t on t.id = r.team_id where r.person_id = pe.id),
    'events', (select coalesce(jsonb_agg(to_jsonb(ev) order by ev.occurred_at desc), '[]') from public.person_events ev where ev.person_id = pe.id),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'template_name', m.template_name, 'status', m.status,
                   'skip_reason', m.skip_reason, 'error_code', m.error_code, 'scheduled_for', m.scheduled_for, 'sent_at', m.sent_at,
                   'delivered_at', m.delivered_at, 'read_at', m.read_at) order by m.created_at desc), '[]')
                 from public.message_log m where m.person_id = pe.id)
  ) into result
  from public.people pe where pe.id = p_person_id;
  return result;
end $$;

create or replace function public.get_my_registrations() returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', pe.id,
    'full_name', pc.full_name,
    'phone_e164', case when pe.created_at > now() - interval '30 days' then pc.phone_e164 end,
    'neighborhood', nb.name,
    'stage', pe.stage,
    'review_status', pe.review_status,
    'whatsapp_valid', pc.whatsapp_valid,
    'last_message_status', (select m.status from public.message_log m where m.person_id = pe.id order by m.created_at desc limit 1),
    'created_at', pe.created_at)
  from public.people pe
  join public.people_contacts pc on pc.person_id = pe.id
  join public.neighborhoods nb on nb.id = pe.neighborhood_id
  where pe.registered_by = auth.uid() and public.auth_role() in ('evangelist', 'central', 'unit_admin') and pe.anonymized_at is null
  order by pe.created_at desc
$$;

-- Fila por time com colunas restritas. Central/unit_admin podem ler qualquer fila da unidade (modo central única).
create or replace function public.get_team_queue(p_team_kind text) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id, 'person_id', r.person_id, 'referral_type', r.referral_type, 'status', r.status, 'priority', r.priority,
    'flags', r.flags, 'reason', r.reason, 'created_at', r.created_at, 'first_response_at', r.first_response_at,
    'assigned_to', r.assigned_to, 'team_kind', t.kind,
    'full_name', pc.full_name,
    'neighborhood', nb.name,
    'phone_e164', case when t.kind in ('basic_food', 'home_items', 'logistics', 'follow_up', 'central') then pc.phone_e164 end,
    'address', case when t.kind in ('basic_food', 'home_items', 'logistics', 'central') then
      jsonb_build_object('kind', pc.address_kind, 'street', pc.street, 'number', pc.number, 'complement', pc.complement,
                         'postal_code', pc.postal_code, 'reference', pc.address_raw) end,
    'children_count', pe.children_count,
    'children_bands', (select coalesce(jsonb_agg(c.age_band order by c.age_band), '[]') from public.children c where c.person_id = pe.id),
    'household_children', (select h.children_count from public.households h where h.id = pe.household_id),
    'needs', (select coalesce(jsonb_agg(jsonb_build_object('type', n.need_type, 'item', n.item_code, 'status', n.status)), '[]')
              from public.needs n where n.person_id = pe.id and n.status not in ('fulfilled', 'cancelled')))
  from public.referrals r
  join public.teams t on t.id = r.team_id
  join public.people pe on pe.id = r.person_id
  join public.people_contacts pc on pc.person_id = pe.id
  join public.neighborhoods nb on nb.id = pe.neighborhood_id
  where t.kind = p_team_kind
    and r.status not in ('done', 'cancelled')
    and pe.anonymized_at is null
    and (public.can_write_unit(r.unit_id) or (public.auth_role() = 'team_member' and r.team_id = any (public.auth_team_ids())))
  order by r.priority, r.created_at
$$;

-- ---------------------------------------------------------------------------
-- WhatsApp inbound (chamadas pela Edge Function com service_role)
-- ---------------------------------------------------------------------------
create or replace function public.resolve_person_by_wa(p_unit_id uuid, p_wa_id text, p_phone_e164 text) returns uuid
language sql stable security definer set search_path = public as $$
  select pc.person_id from public.people_contacts pc join public.people pe on pe.id = pc.person_id
  where pc.unit_id = p_unit_id and pe.anonymized_at is null
    and (pc.wa_id = p_wa_id or pc.phone_e164 = any (public.phone_variants(p_phone_e164)))
  order by (pc.wa_id = p_wa_id) desc, pc.is_primary desc, (pe.review_status = 'ok') desc, pe.created_at desc
  limit 1
$$;

create or replace function public.opt_out_person(p_unit_id uuid, p_phone_e164 text, p_reason text default 'SAIR') returns integer
language plpgsql security definer set search_path = public as $$
declare v_count integer := 0; r record;
begin
  perform public.assert_service_role();
  for r in select pc.person_id from public.people_contacts pc join public.people pe on pe.id = pc.person_id
           where pc.unit_id = p_unit_id and pe.anonymized_at is null and pc.phone_e164 = any (public.phone_variants(p_phone_e164)) loop
    update public.consents set revoked_at = now(), revoke_reason = p_reason
    where person_id = r.person_id and purpose in ('whatsapp_contact', 'marketing_events') and revoked_at is null;
    update public.message_log set status = 'skipped', skip_reason = 'opted_out' where person_id = r.person_id and status = 'queued';
    update public.people set stage = 'opted_out', last_contact_at = now() where id = r.person_id;
    insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, r.person_id, 'opted_out', jsonb_build_object('reason', p_reason));
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create or replace function public.confirm_optin(p_unit_id uuid, p_person_id uuid, p_wamid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_service_role();
  update public.consents set confirmed_at = coalesce(confirmed_at, now()), confirmation_wamid = coalesce(confirmation_wamid, p_wamid)
  where person_id = p_person_id and purpose = 'whatsapp_contact' and granted and revoked_at is null;
  update public.people set stage = 'journey_active', optin_confirmed_at = coalesce(optin_confirmed_at, now()), last_contact_at = now()
  where id = p_person_id and unit_id = p_unit_id and stage in ('registered', 'first_contact_pending', 'paused', 'inactive');
  insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, p_person_id, 'optin_confirmed', jsonb_build_object('wamid', p_wamid));
end $$;

create or replace function public.enqueue_video1(p_unit_id uuid, p_person_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_asset uuid; v_phone text; v_id uuid;
begin
  select ca.id into v_asset from public.content_assets ca
  where ca.key = 'video_1' and ca.active and (ca.unit_id = p_unit_id or ca.unit_id is null) order by ca.unit_id nulls last limit 1;
  select phone_e164 into v_phone from public.people_contacts where person_id = p_person_id;
  if v_asset is null or v_phone is null then return null; end if;
  insert into public.message_log (unit_id, person_id, to_phone_e164, kind, content_asset_id, status, scheduled_for, payload)
  values (p_unit_id, p_person_id, v_phone, 'media', v_asset, 'queued', now(), jsonb_build_object('buttons', '[{"id":"video_watched","title":"Assisti até o final"}]'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.handle_inbound(p_unit_id uuid, p_wa_id text, p_phone_e164 text, p_kind text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_person uuid; v_button text; v_text text; v_norm text; v_team uuid; v_stage text; v_ref uuid; v_wamid text; v_action text := 'none';
begin
  perform public.assert_service_role();
  v_wamid := p_payload->>'wamid';
  v_person := public.resolve_person_by_wa(p_unit_id, p_wa_id, p_phone_e164);
  if v_person is null then
    return jsonb_build_object('action', 'unknown_sender');
  end if;
  update public.people_contacts set wa_id = coalesce(wa_id, p_wa_id) where person_id = v_person;
  update public.people set last_contact_at = now() where id = v_person;
  select stage into v_stage from public.people where id = v_person;

  if p_kind = 'button' then
    v_button := p_payload->>'button_id';
    if v_button = 'optin_yes' then
      perform public.confirm_optin(p_unit_id, v_person, v_wamid);
      perform public.enqueue_video1(p_unit_id, v_person);
      v_action := 'optin_confirmed_video_queued';
    elsif v_button = 'video_watched' then
      if v_stage in ('registered', 'first_contact_pending', 'paused', 'inactive') then
        perform public.confirm_optin(p_unit_id, v_person, v_wamid);
      end if;
      insert into public.person_events (unit_id, person_id, event_type, payload)
      values (p_unit_id, v_person, 'video_watched', jsonb_build_object('wamid', v_wamid, 'content_key', 'video_1'));
      v_action := 'video_watched';
    elsif v_button = 'optin_no' then
      update public.people set stage = 'paused' where id = v_person and stage in ('registered', 'first_contact_pending');
      update public.message_log set status = 'skipped', skip_reason = 'paused' where person_id = v_person and status = 'queued';
      v_action := 'paused';
    elsif v_button = 'stop' then
      perform public.opt_out_person(p_unit_id, p_phone_e164, 'botão Parar');
      v_action := 'opted_out';
    end if;
  elsif p_kind = 'text' then
    v_text := coalesce(p_payload->>'text', '');
    v_norm := public.normalize_text(v_text);
    if v_norm ~ '^(sair|parar|cancelar|pare|stop)\W*$' then
      perform public.opt_out_person(p_unit_id, p_phone_e164, 'SAIR');
      v_action := 'opted_out';
    elsif v_norm ~ '^meus dados\W*$' then
      insert into public.person_events (unit_id, person_id, event_type, payload)
      values (p_unit_id, v_person, 'data_request', jsonb_build_object('wamid', v_wamid, 'deadline', (now() + interval '15 days')::date));
      insert into public.notifications (unit_id, recipient_profile_id, kind, title, ref_table, ref_id)
      select p_unit_id, pr.id, 'data_request', 'Pedido de dados (LGPD) — prazo 15 dias', 'people', v_person
      from public.profiles pr where pr.unit_id = p_unit_id and pr.active and pr.role in ('central', 'unit_admin');
      v_action := 'data_request';
    else
      -- texto livre: resposta fixa dentro da janela de 24 h + encaminhamento ao acompanhamento (regra 50)
      select t.id into v_team from public.teams t where t.unit_id = p_unit_id and t.kind = 'follow_up' and t.active
        and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
      if v_team is null then select t.id into v_team from public.teams t where t.unit_id = p_unit_id and t.kind = 'central'; end if;
      if not exists (select 1 from public.referrals r where r.person_id = v_person and r.referral_type = 'follow_up' and r.status not in ('done', 'cancelled')) then
        insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority)
        values (p_unit_id, v_person, v_team, 'follow_up', 'mensagem no WhatsApp: ' || left(v_text, 80), 1) returning id into v_ref;
        insert into public.referral_events (unit_id, referral_id, to_status, note) values (p_unit_id, v_ref, 'new', 'inbound');
        insert into public.notifications (unit_id, team_id, kind, title, ref_table, ref_id)
        values (p_unit_id, v_team, 'referral', 'Mensagem recebida no WhatsApp', 'referrals', v_ref);
      end if;
      insert into public.person_events (unit_id, person_id, event_type, payload)
      values (p_unit_id, v_person, 'note', jsonb_build_object('wamid', v_wamid, 'inbound_text', left(v_text, 500)));
      if exists (select 1 from public.consents c where c.person_id = v_person and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null) then
        insert into public.message_log (unit_id, person_id, to_phone_e164, kind, status, scheduled_for, payload)
        values (p_unit_id, v_person, p_phone_e164, 'text', 'queued', now(),
                jsonb_build_object('text', 'Recebemos sua mensagem. Alguém da equipe do Transtornar vai falar com você em breve. Para parar de receber mensagens, responda SAIR.'));
      end if;
      v_action := 'free_text_referred';
    end if;
  end if;
  return jsonb_build_object('action', v_action, 'person_id', v_person);
end $$;

-- ---------------------------------------------------------------------------
-- LGPD: anonimização e retenção
-- ---------------------------------------------------------------------------
create or replace function public.anonymize_person(p_person_id uuid, p_reason text default 'request') returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  if v_unit is null then raise exception 'person_not_found'; end if;
  if not (public.can_write_unit(v_unit) or coalesce(auth.role(), '') = 'service_role' or current_user in ('postgres', 'supabase_admin')) then
    raise insufficient_privilege;
  end if;
  delete from public.people_contacts where person_id = p_person_id;
  delete from public.children where person_id = p_person_id;
  update public.needs set raw_text = null where person_id = p_person_id;
  update public.referrals set reason = referral_type, status = case when status in ('done', 'cancelled') then status else 'cancelled' end,
         cancelled_reason = case when status in ('done', 'cancelled') then cancelled_reason else 'anonymized' end
  where person_id = p_person_id;
  update public.notifications set title = 'Pessoa anonimizada' where ref_table = 'people' and ref_id = p_person_id;
  update public.notifications set title = 'Pessoa anonimizada' where ref_table = 'referrals' and ref_id in (select id from public.referrals where person_id = p_person_id);
  update public.message_log set to_phone_e164 = null, status = case when status = 'queued' then 'skipped' else status end,
         skip_reason = case when status = 'queued' then 'anonymized' else skip_reason end,
         payload = jsonb_build_object('template', template_name)
  where person_id = p_person_id;
  update public.audit_log set diff = null where table_name = 'people' and row_id = p_person_id;
  update public.people set observation = null, stage = 'anonymized', anonymized_at = now(), review_status = case when review_status = 'merged' then 'merged' else review_status end
  where id = p_person_id;
  -- person_events é append-only: bypass explícito e local à transação (depois da mudança de estágio)
  perform set_config('app.bypass_append_only', 'on', true);
  update public.person_events set payload = '{}'::jsonb where person_id = p_person_id;
  perform set_config('app.bypass_append_only', 'off', true);
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload)
  values (v_unit, p_person_id, 'anonymized', auth.uid(), jsonb_build_object('reason', p_reason));
end $$;

create or replace function public.run_retention_policy() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_inactive integer := 0; v_anon integer := 0; r record; v_team uuid;
begin
  perform public.assert_service_role();
  -- (a) silêncio após o lembrete (+48 h) + 14 dias => inativo + contato humano; nunca anonimização por silêncio
  for r in select pe.id, pe.unit_id from public.people pe
           where pe.stage = 'first_contact_pending' and pe.first_contact_sent_at < now() - interval '16 days'
             and pe.last_contact_at is null loop
    update public.people set stage = 'inactive' where id = r.id;
    select t.id into v_team from public.teams t where t.unit_id = r.unit_id and t.kind = 'follow_up' and t.active
      and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
    if v_team is null then select t.id into v_team from public.teams t where t.unit_id = r.unit_id and t.kind = 'central'; end if;
    if not exists (select 1 from public.referrals x where x.person_id = r.id and x.referral_type = 'follow_up' and x.status not in ('done', 'cancelled')) then
      insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority)
      values (r.unit_id, r.id, v_team, 'follow_up', 'sem resposta no WhatsApp: contato humano', 2);
    end if;
    insert into public.person_events (unit_id, person_id, event_type, payload) values (r.unit_id, r.id, 'contact_attempt', '{"channel":"whatsapp","result":"no_response"}');
    v_inactive := v_inactive + 1;
  end loop;
  -- (b) opt-out há 30 dias => anonimização
  for r in select pe.id from public.people pe where pe.stage = 'opted_out' and pe.stage_changed_at < now() - interval '30 days' loop
    perform public.anonymize_person(r.id, 'opted_out');
    v_anon := v_anon + 1;
  end loop;
  -- (c) eventos brutos do webhook: 90 dias
  delete from public.wa_inbound_events where created_at < now() - interval '90 days';
  return jsonb_build_object('inactivated', v_inactive, 'anonymized', v_anon);
end $$;

-- ---------------------------------------------------------------------------
-- Convites
-- ---------------------------------------------------------------------------
create or replace function public.create_invite(p_email text, p_role text, p_team_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id(); v_code text; v_id uuid;
begin
  perform public.assert_role('unit_admin', 'global_admin');
  if v_unit is null then raise exception 'unit_required'; end if;
  if p_team_id is not null and not exists (select 1 from public.teams t where t.id = p_team_id and t.unit_id = v_unit) then raise exception 'team_not_in_unit'; end if;
  v_code := lower(encode(extensions.gen_random_bytes(6), 'hex'));
  insert into public.invites (unit_id, email, role, team_id, code, invited_by, expires_at)
  values (v_unit, lower(trim(p_email)), p_role, p_team_id, v_code, auth.uid(), now() + interval '7 days')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'code', v_code, 'expires_at', now() + interval '7 days');
end $$;

create or replace function public.get_invite(p_code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('email', i.email, 'role', i.role, 'unit_name', u.name, 'expires_at', i.expires_at, 'accepted', i.accepted_at is not null)
  from public.invites i join public.units u on u.id = i.unit_id
  where i.code = p_code and i.expires_at > now()
$$;

create or replace function public.accept_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i record; v_email text; v_name text;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  v_email := lower(coalesce(auth.jwt()->>'email', ''));
  select * into i from public.invites where code = p_code and expires_at > now() and accepted_at is null;
  if not found then raise exception 'invite_invalid'; end if;
  if i.email <> v_email then raise exception 'invite_email_mismatch'; end if;
  v_name := coalesce(auth.jwt()->'user_metadata'->>'full_name', split_part(v_email, '@', 1));
  insert into public.profiles (id, unit_id, full_name, role, invited_by, volunteer_terms_version, volunteer_terms_accepted_at)
  values (auth.uid(), i.unit_id, v_name, i.role, i.invited_by, 'v1', now())
  on conflict (id) do update set unit_id = excluded.unit_id, role = excluded.role, active = true;
  if i.team_id is not null then
    insert into public.team_members (unit_id, team_id, profile_id) values (i.unit_id, i.team_id, auth.uid()) on conflict do nothing;
  end if;
  update public.invites set accepted_at = now() where id = i.id;
  return jsonb_build_object('role', i.role, 'unit_id', i.unit_id);
end $$;

-- ---------------------------------------------------------------------------
-- Franquia: clona catálogos globais para uma nova unidade
-- ---------------------------------------------------------------------------
create or replace function public.clone_unit_defaults(p_new_unit_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_role('global_admin');
  insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type, auto_triage, active)
  select p_new_unit_id, name, priority, condition, target_team_kind, referral_type, auto_triage, active from public.routing_rules where unit_id is null;
  insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables)
  select p_new_unit_id, name, language, category, 'pending', header_type, body_text, buttons, variables from public.message_templates where unit_id is null
  on conflict do nothing;
  insert into public.teams (unit_id, kind, name, active)
  select p_new_unit_id, k.kind, k.name, k.kind = 'central' from (values ('central', 'Central'), ('basic_food', 'Cesta básica'), ('follow_up', 'Acompanhamento'),
    ('strategy', 'Estratégia'), ('home_items', 'Itens de casa'), ('education', 'Educação'), ('employment', 'Trabalho'), ('logistics', 'Logística')) as k(kind, name)
  on conflict do nothing;
end $$;

-- ---------------------------------------------------------------------------
-- Views agregadas (security_invoker: quem não lê people vê vazio)
-- ---------------------------------------------------------------------------
create or replace view public.v_conversions_by_neighborhood with (security_invoker = true) as
  select pe.unit_id, pe.neighborhood_id, nb.name as neighborhood,
         count(*) filter (where pe.review_status <> 'merged') as people_total,
         count(*) filter (where pe.review_status <> 'merged' and pe.decided_at > now() - interval '30 days') as people_30d,
         count(*) filter (where pe.stage = 'journey_active') as journey_active
  from public.people pe join public.neighborhoods nb on nb.id = pe.neighborhood_id
  group by pe.unit_id, pe.neighborhood_id, nb.name;

create or replace view public.v_decisions_total_by_neighborhood with (security_invoker = true) as
  select x.unit_id, x.neighborhood_id, nb.name as neighborhood, sum(x.registered) as registered, sum(x.tally) as tally, sum(x.minors) as minors,
         sum(x.registered + x.tally) as decisions_total
  from (
    select unit_id, neighborhood_id, count(*) filter (where review_status <> 'merged') as registered, 0 as tally, 0 as minors
    from public.people group by unit_id, neighborhood_id
    union all
    select unit_id, neighborhood_id, 0, sum(count), sum(minor_count) from public.decision_tally group by unit_id, neighborhood_id
  ) x join public.neighborhoods nb on nb.id = x.neighborhood_id
  group by x.unit_id, x.neighborhood_id, nb.name;

create or replace view public.v_impact_public with (security_invoker = true) as
  select unit_id, neighborhood, decisions_total from public.v_decisions_total_by_neighborhood where decisions_total >= 5;

-- ---------------------------------------------------------------------------
-- Jobs: worker de envio a cada minuto e retenção semanal (só quando pg_cron existe)
-- ---------------------------------------------------------------------------
create or replace function public.invoke_edge(p_function text) returns void
language plpgsql security definer set search_path = public as $$
declare v_base text; v_secret text;
begin
  select value #>> '{}' into v_base from public.app_settings where key = 'edge_base_url' order by unit_id limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'edge_shared_secret' limit 1;
  if v_base is null or v_secret is null then return; end if;
  perform net.http_post(
    url := v_base || '/' || p_function,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret, 'x-region', 'sa-east-1'),
    timeout_milliseconds := 5000);
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('whatsapp-send', '* * * * *', $c$ select public.invoke_edge('whatsapp-send') $c$);
    perform cron.schedule('lgpd-retention', '0 4 * * 1', $c$ select public.run_retention_policy() $c$);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Grants das RPCs
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.register_person(jsonb), public.record_decision_tally(uuid, boolean), public.referral_transition(uuid, text, text),
  public.mark_duplicate(uuid, uuid), public.confirm_distinct_person(uuid), public.open_person_record(uuid), public.get_my_registrations(),
  public.get_team_queue(text), public.anonymize_person(uuid, text), public.create_invite(text, text, uuid), public.accept_invite(text),
  public.clone_unit_defaults(uuid), public.auth_unit_id(), public.auth_role(), public.auth_team_ids(), public.is_unit_staff(),
  public.can_read_unit(uuid), public.can_write_unit(uuid), public.normalize_text(text), public.normalize_e164(text), public.find_neighborhood(uuid, text)
  to authenticated;
grant execute on function public.get_invite(text), public.normalize_text(text) to anon;
grant execute on all functions in schema public to service_role;

-- ---------------------------------------------------------------------------
-- RLS em todas as tabelas
-- ---------------------------------------------------------------------------
alter table public.units enable row level security;
alter table public.cities enable row level security;
alter table public.neighborhoods enable row level security;
alter table public.unit_neighborhoods enable row level security;
alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.invites enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.households enable row level security;
alter table public.people enable row level security;
alter table public.people_contacts enable row level security;
alter table public.children enable row level security;
alter table public.needs enable row level security;
alter table public.consents enable row level security;
alter table public.decision_tally enable row level security;
alter table public.person_events enable row level security;
alter table public.routing_rules enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_events enable row level security;
alter table public.notifications enable row level security;
alter table public.message_templates enable row level security;
alter table public.content_assets enable row level security;
alter table public.message_log enable row level security;
alter table public.wa_inbound_events enable row level security;
alter table public.audit_log enable row level security;

-- referência e tenancy
create policy units_select on public.units for select to authenticated using (public.can_read_unit(id));
create policy units_update on public.units for update to authenticated using (id = public.auth_unit_id() and public.auth_role() = 'unit_admin');
create policy units_admin_write on public.units for all to authenticated using (public.auth_role() = 'global_admin') with check (public.auth_role() = 'global_admin');
create policy cities_select on public.cities for select to authenticated using (true);
create policy cities_write on public.cities for all to authenticated using (public.auth_role() = 'global_admin') with check (public.auth_role() = 'global_admin');
create policy neighborhoods_select on public.neighborhoods for select to authenticated using (true);
create policy neighborhoods_write on public.neighborhoods for all to authenticated using (public.auth_role() = 'global_admin') with check (public.auth_role() = 'global_admin');
create policy unit_neighborhoods_select on public.unit_neighborhoods for select to authenticated using (public.can_read_unit(unit_id));
create policy unit_neighborhoods_write on public.unit_neighborhoods for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy app_settings_select on public.app_settings for select to authenticated
  using ((is_public and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin') or public.auth_role() = 'global_admin');
create policy app_settings_write on public.app_settings for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));

-- acesso
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or (public.is_unit_staff() and public.can_read_unit(unit_id)) or public.auth_role() = 'global_admin');
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role = public.auth_role() and unit_id is not distinct from public.auth_unit_id());
create policy profiles_admin on public.profiles for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin' and role <> 'global_admin'));
create policy invites_admin on public.invites for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy teams_select on public.teams for select to authenticated using (public.can_read_unit(unit_id));
create policy teams_write on public.teams for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy team_members_select on public.team_members for select to authenticated using (profile_id = auth.uid() or public.can_read_unit(unit_id));
create policy team_members_write on public.team_members for all to authenticated
  using (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check (public.auth_role() = 'global_admin' or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));

-- dados sensíveis: só central/unit_admin da unidade (leitura+escrita) e global_admin (leitura)
create policy households_staff on public.households for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy people_staff on public.people for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy people_contacts_staff on public.people_contacts for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy children_staff on public.children for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy needs_staff on public.needs for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy consents_staff on public.consents for all to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy decision_tally_staff on public.decision_tally for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy person_events_staff on public.person_events for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy person_events_insert on public.person_events for insert to authenticated with check (public.can_write_unit(unit_id));

-- catálogos: globais (unit_id null) + da unidade
create policy routing_rules_select on public.routing_rules for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy routing_rules_write on public.routing_rules for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy message_templates_select on public.message_templates for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy message_templates_write on public.message_templates for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy content_assets_select on public.content_assets for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy content_assets_write on public.content_assets for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));

-- filas
create policy referrals_select on public.referrals for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or team_id = any (public.auth_team_ids()));
create policy referrals_write on public.referrals for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy referral_events_select on public.referral_events for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or exists (select 1 from public.referrals r where r.id = referral_id and r.team_id = any (public.auth_team_ids())));
create policy referral_events_insert on public.referral_events for insert to authenticated with check (public.can_write_unit(unit_id));
create policy notifications_select on public.notifications for select to authenticated
  using (recipient_profile_id = auth.uid() or team_id = any (public.auth_team_ids()) or public.can_write_unit(unit_id));
create policy notifications_update on public.notifications for update to authenticated
  using (recipient_profile_id = auth.uid() or team_id = any (public.auth_team_ids()) or public.can_write_unit(unit_id));

-- logs: leitura por staff; escrita só service_role
create policy message_log_staff on public.message_log for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy wa_inbound_events_staff on public.wa_inbound_events for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy audit_log_staff on public.audit_log for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
