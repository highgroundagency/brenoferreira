-- 008 — Fase 2a: jornada "primeiros passos da vida com Deus", perguntas de perfil, gamificação, CRM de acompanhamento,
-- programa de cesta básica por 3 meses com entregas, mesclagem de duplicatas, retenção v2, Realtime.

-- ---------------------------------------------------------------------------
-- Colunas e enums novos
-- ---------------------------------------------------------------------------
alter table public.people drop constraint people_stage_check;
alter table public.people add constraint people_stage_check check (stage in
  ('registered', 'first_contact_pending', 'journey_active', 'day7_done', 'day16_done', 'church_connected', 'supporter',
   'paused', 'inactive', 'opted_out', 'anonymized'));
alter table public.people
  add column income_range text check (income_range in ('up_to_1_mw', '1_3_mw', 'over_3_mw', 'prefer_not')),
  add column profile_segment text check (profile_segment in ('support', 'general', 'business', 'supporter_prospect')),
  add column case_summary text,
  add column source_event_id uuid,
  add column assigned_to uuid references public.profiles(id),
  add column points integer not null default 0;
alter table public.team_members drop constraint team_members_member_role_check;
alter table public.team_members add constraint team_members_member_role_check check (member_role in ('member', 'lead', 'instructor', 'driver'));
alter table public.message_log add column pricing_category text, add column cost_estimate numeric(10, 4);
alter table public.consents drop constraint consents_purpose_check;
alter table public.consents add constraint consents_purpose_check check (purpose in
  ('spiritual_followup', 'social_assistance', 'whatsapp_contact', 'marketing_events', 'share_with_church', 'share_with_employer', 'education_minor', 'benefits_club'));
alter table public.person_events drop constraint person_events_event_type_check;
alter table public.person_events add constraint person_events_event_type_check check (event_type in
  ('registered', 'referral_created', 'message_sent', 'optin_confirmed', 'video_watched', 'opted_out', 'stage_changed',
   'contact_attempt', 'data_request', 'anonymized', 'duplicate_marked', 'distinct_confirmed', 'need_added', 'note',
   'journey_step_sent', 'journey_step_skipped', 'feedback', 'reward_earned', 'reward_delivered', 'profile_answer',
   'delivery_status', 'follow_up', 'merged', 'church_interest', 'event_invited', 'event_rsvp', 'event_checkin', 'enrolled', 'job_placement', 'imported'));
alter table public.referrals drop constraint referrals_referral_type_check;
alter table public.referrals add constraint referrals_referral_type_check check (referral_type in
  ('basic_food', 'home_items', 'education', 'employment', 'follow_up', 'strategy_review', 'reward_delivery', 'church_connection', 'other'));
update public.units set settings = settings || '{"monthly_message_cap": 5000, "same_day_cutoff": "14:00", "ai_enabled": false, "basic_food_months": 3, "basic_food_frequency_days": 30}'::jsonb;

-- ---------------------------------------------------------------------------
-- Jornada
-- ---------------------------------------------------------------------------
create table public.journey_steps (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),             -- null = global
  journey_key text not null default 'primeiros_passos',
  sequence integer not null,
  day_offset integer not null,                          -- dias após o início da jornada
  title text not null,
  template_name text not null default 'transtornar_jornada_v1',
  content_key text,                                     -- content_assets.key (vídeo); null para perguntas
  question_kind text check (question_kind in ('income', 'events_optin', 'church')),
  audience_segment text,                                -- null = todos
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, journey_key, sequence)
);
create trigger journey_steps_set_updated_at before update on public.journey_steps for each row execute function public.set_updated_at();

create table public.person_journeys (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null unique references public.people(id) on delete cascade,
  journey_key text not null default 'primeiros_passos',
  current_sequence integer not null default 0,
  completed_steps integer not null default 0,
  started_at timestamptz not null default now(),
  next_send_at timestamptz,
  last_step_sent_at timestamptz,
  status text not null default 'active' check (status in ('active', 'paused', 'completed', 'stopped')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index person_journeys_due_idx on public.person_journeys (next_send_at) where status = 'active';
create trigger person_journeys_set_updated_at before update on public.person_journeys for each row execute function public.set_updated_at();

create table public.journey_progress (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  step_id uuid not null references public.journey_steps(id),
  sequence integer not null,
  status text not null default 'sent' check (status in ('sent', 'skipped', 'watched', 'answered')),
  message_log_id uuid references public.message_log(id),
  sent_at timestamptz,
  watched_at timestamptz,
  feedback_score smallint check (feedback_score between 1 and 3),
  feedback_at timestamptz,
  answer text,
  created_at timestamptz not null default now(),
  unique (person_id, step_id)
);
create index journey_progress_person_idx on public.journey_progress (person_id, sequence);

-- ---------------------------------------------------------------------------
-- Gamificação: marcos (dias de conteúdo / dias corridos / pontos)
-- ---------------------------------------------------------------------------
create table public.reward_rules (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),
  key text not null,
  name text not null,
  condition_type text not null check (condition_type in ('step_completed', 'milestone_days', 'points_threshold')),
  threshold integer not null,
  item text not null,                                   -- Bíblia, livrinho...
  stage_on_earn text,                                   -- day7_done | day16_done | null
  message_text text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (unit_id, key)
);
create table public.reward_grants (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  rule_id uuid not null references public.reward_rules(id),
  earned_at timestamptz not null default now(),
  delivered_at timestamptz,
  referral_id uuid references public.referrals(id),
  unique (person_id, rule_id)
);
create table public.point_rules (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),
  event_type text not null,
  points integer not null,
  active boolean not null default true,
  unique (unit_id, event_type)
);
create table public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  event_type text not null,
  points integer not null,
  ref_id uuid,
  earned_at timestamptz not null default now()
);
create index points_ledger_person_idx on public.points_ledger (person_id);

-- ---------------------------------------------------------------------------
-- CRM de acompanhamento
-- ---------------------------------------------------------------------------
create table public.follow_ups (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  member_id uuid references public.profiles(id),
  channel text not null default 'whatsapp' check (channel in ('whatsapp', 'phone', 'visit', 'church', 'other')),
  note text not null,
  next_action_at timestamptz,
  done_at timestamptz,
  created_at timestamptz not null default now()
);
create index follow_ups_person_idx on public.follow_ups (person_id, created_at desc);
create index follow_ups_next_idx on public.follow_ups (unit_id, next_action_at) where done_at is null;

-- ---------------------------------------------------------------------------
-- Logística: programa de cesta básica e entregas
-- ---------------------------------------------------------------------------
create table public.assistance_programs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  household_id uuid references public.households(id),
  person_id uuid not null references public.people(id) on delete cascade,
  referral_id uuid references public.referrals(id),
  program_type text not null default 'basic_food' check (program_type in ('basic_food', 'home_items')),
  start_date date not null default current_date,
  end_date date not null,
  planned_deliveries integer not null,
  completed_deliveries integer not null default 0,
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  created_by uuid references public.profiles(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index assistance_programs_one_active_per_household on public.assistance_programs (household_id, program_type) where status = 'active' and household_id is not null;
create trigger assistance_programs_set_updated_at before update on public.assistance_programs for each row execute function public.set_updated_at();

create table public.delivery_orders (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  program_id uuid references public.assistance_programs(id) on delete cascade,
  referral_id uuid references public.referrals(id),
  person_id uuid not null references public.people(id) on delete cascade,
  household_id uuid references public.households(id),
  kind text not null check (kind in ('basic_food', 'home_item', 'reward')),
  item_code text,
  status text not null default 'scheduled' check (status in ('scheduled', 'picking', 'packed', 'out_for_delivery', 'delivered', 'failed', 'cancelled')),
  scheduled_for date not null default current_date,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  driver_id uuid references public.profiles(id),
  address_snapshot jsonb,
  proof_note text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index delivery_orders_queue_idx on public.delivery_orders (unit_id, status, scheduled_for);
create trigger delivery_orders_set_updated_at before update on public.delivery_orders for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Seeds globais (templates, passos, marcos, pontos, conteúdos-placeholder)
-- ---------------------------------------------------------------------------
insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables) values
  (null, 'transtornar_jornada_v1', 'pt_BR', 'MARKETING', 'pending', 'video',
   'Olá {{1}}! Passo de hoje na sua caminhada com Deus: {{2}}. Para parar a qualquer momento, responda SAIR.',
   '[{"id":"video_watched","title":"Assisti até o final"},{"id":"stop","title":"Parar"}]', '["first_name","step_title"]'),
  (null, 'transtornar_renda_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   '{{1}}, para a gente entender melhor como ajudar: mais ou menos quanto entra na sua casa por mês? Se preferir, não responda.',
   '[{"id":"income_up_to_1_mw","title":"Até 1 salário"},{"id":"income_1_3_mw","title":"1 a 3 salários"},{"id":"income_over_3_mw","title":"Mais de 3"}]', '["first_name"]'),
  (null, 'transtornar_eventos_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   '{{1}}, o Transtornar faz encontros no seu bairro. Quer receber convites?',
   '[{"id":"events_yes","title":"Quero convites"},{"id":"events_no","title":"Não quero"}]', '["first_name"]'),
  (null, 'transtornar_igreja_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   '{{1}}, quer conhecer uma igreja perto de você para caminhar junto com outras pessoas?',
   '[{"id":"church_yes","title":"Quero conhecer"},{"id":"church_have","title":"Já tenho igreja"},{"id":"church_no","title":"Agora não"}]', '["first_name"]'),
  (null, 'transtornar_entrega_v1', 'pt_BR', 'UTILITY', 'pending', 'none',
   'Olá {{1}}, aqui é o Transtornar: {{2}}',
   '[]', '["first_name","status_text"]')
on conflict do nothing;

insert into public.content_assets (unit_id, key, title, media_type, public_url, source, rights_ok, active) values
  (null, 'video_2', 'Como orar', 'video', 'https://example.invalid/video_2.mp4', 'new', false, false),
  (null, 'video_3', 'A Bíblia no dia a dia', 'video', 'https://example.invalid/video_3.mp4', 'new', false, false),
  (null, 'video_4', 'Caminhar em comunidade', 'video', 'https://example.invalid/video_4.mp4', 'new', false, false),
  (null, 'video_5', 'Perdão e recomeço', 'video', 'https://example.invalid/video_5.mp4', 'new', false, false),
  (null, 'video_6', 'Uma igreja para chamar de sua', 'video', 'https://example.invalid/video_6.mp4', 'new', false, false),
  (null, 'video_7', 'Servir e cuidar', 'video', 'https://example.invalid/video_7.mp4', 'new', false, false),
  (null, 'video_8', 'Próximos passos', 'video', 'https://example.invalid/video_8.mp4', 'new', false, false)
on conflict do nothing;

insert into public.journey_steps (unit_id, journey_key, sequence, day_offset, title, template_name, content_key, question_kind) values
  (null, 'primeiros_passos', 1, 0, 'A importância de Jesus', 'transtornar_video1_v1', 'video_1', null),
  (null, 'primeiros_passos', 2, 2, 'Como orar', 'transtornar_jornada_v1', 'video_2', null),
  (null, 'primeiros_passos', 3, 4, 'A Bíblia no dia a dia', 'transtornar_jornada_v1', 'video_3', null),
  (null, 'primeiros_passos', 4, 7, 'Caminhar em comunidade', 'transtornar_jornada_v1', 'video_4', null),
  (null, 'primeiros_passos', 5, 8, 'Pergunta: renda', 'transtornar_renda_v1', null, 'income'),
  (null, 'primeiros_passos', 6, 9, 'Perdão e recomeço', 'transtornar_jornada_v1', 'video_5', null),
  (null, 'primeiros_passos', 7, 11, 'Uma igreja para chamar de sua', 'transtornar_jornada_v1', 'video_6', null),
  (null, 'primeiros_passos', 8, 12, 'Pergunta: igreja', 'transtornar_igreja_v1', null, 'church'),
  (null, 'primeiros_passos', 9, 14, 'Servir e cuidar', 'transtornar_jornada_v1', 'video_7', null),
  (null, 'primeiros_passos', 10, 16, 'Próximos passos', 'transtornar_jornada_v1', 'video_8', null),
  (null, 'primeiros_passos', 11, 17, 'Pergunta: convites', 'transtornar_eventos_v1', null, 'events_optin')
on conflict do nothing;

insert into public.reward_rules (unit_id, key, name, condition_type, threshold, item, stage_on_earn, message_text) values
  (null, 'day7', '7 dias de conteúdo', 'step_completed', 4, 'Bíblia', 'day7_done', 'Parabéns, {{1}}! Você completou 7 dias de conteúdo com Deus e vai receber uma Bíblia do Transtornar.'),
  (null, 'day16', '16 dias de conteúdo', 'step_completed', 8, 'Livrinho', 'day16_done', 'Que caminhada, {{1}}! 16 dias de conteúdo concluídos. Um livrinho especial está a caminho para você.')
on conflict do nothing;

insert into public.point_rules (unit_id, event_type, points) values
  (null, 'video_watched', 10), (null, 'feedback', 5), (null, 'profile_answer', 5), (null, 'church_connected', 20), (null, 'event_checkin', 20)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Funções da jornada
-- ---------------------------------------------------------------------------
create or replace function public.journey_steps_for(p_unit_id uuid, p_key text) returns setof public.journey_steps
language sql stable as $$
  select * from public.journey_steps js
  where js.active and js.journey_key = p_key
    and js.unit_id is not distinct from (case when exists (select 1 from public.journey_steps x where x.unit_id = p_unit_id and x.journey_key = p_key) then p_unit_id else null end)
  order by js.sequence
$$;

create or replace function public.add_points(p_person_id uuid, p_event_type text, p_ref_id uuid default null) returns integer
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_points integer;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  select pr.points into v_points from public.point_rules pr
  where pr.active and pr.event_type = p_event_type and (pr.unit_id = v_unit or pr.unit_id is null) order by pr.unit_id nulls last limit 1;
  if v_points is null then return 0; end if;
  insert into public.points_ledger (unit_id, person_id, event_type, points, ref_id) values (v_unit, p_person_id, p_event_type, v_points, p_ref_id);
  update public.people set points = points + v_points where id = p_person_id;
  return v_points;
end $$;

-- Inicia a jornada ao confirmar o opt-in; o passo 1 (vídeo 1) já foi enviado como primeiro contato
create or replace function public.start_journey(p_person_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare p record; s1 record; s2 record; v_id uuid; v_msg uuid;
begin
  select id, unit_id into p from public.people where id = p_person_id;
  if p.id is null then return null; end if;
  if exists (select 1 from public.person_journeys where person_id = p_person_id) then
    update public.person_journeys set status = 'active' where person_id = p_person_id and status = 'paused';
    return (select id from public.person_journeys where person_id = p_person_id);
  end if;
  select * into s1 from public.journey_steps_for(p.unit_id, 'primeiros_passos') where sequence = 1;
  select * into s2 from public.journey_steps_for(p.unit_id, 'primeiros_passos') where sequence = 2;
  insert into public.person_journeys (unit_id, person_id, current_sequence, started_at, next_send_at)
  values (p.unit_id, p_person_id, case when s1.id is not null then 1 else 0 end, now(),
          case when s2.id is not null then public.next_send_slot(p.unit_id, now() + make_interval(days => s2.day_offset)) end)
  returning id into v_id;
  if s1.id is not null then
    select m.id into v_msg from public.message_log m where m.person_id = p_person_id and m.status in ('sent', 'delivered', 'read') order by m.created_at limit 1;
    insert into public.journey_progress (unit_id, person_id, step_id, sequence, status, message_log_id, sent_at, watched_at)
    values (p.unit_id, p_person_id, s1.id, 1, case when exists (select 1 from public.person_events e where e.person_id = p_person_id and e.event_type = 'video_watched') then 'watched' else 'sent' end,
            v_msg, coalesce((select sent_at from public.message_log where id = v_msg), now()),
            (select min(occurred_at) from public.person_events e where e.person_id = p_person_id and e.event_type = 'video_watched'))
    on conflict do nothing;
    update public.person_journeys set completed_steps = (select count(*) from public.journey_progress jp where jp.person_id = p_person_id and jp.status in ('watched', 'answered')) where id = v_id;
  end if;
  return v_id;
end $$;

-- Avalia marcos após um passo concluído; concede prêmio, abre entrega e avisa a pessoa
create or replace function public.evaluate_rewards(p_person_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare p record; j record; r record; v_granted integer := 0; v_team uuid; v_ref uuid; v_phone text; v_first text; v_earned boolean;
begin
  select pe.*, pc.phone_e164, split_part(pc.full_name, ' ', 1) as first_name into p
  from public.people pe left join public.people_contacts pc on pc.person_id = pe.id where pe.id = p_person_id;
  select * into j from public.person_journeys where person_id = p_person_id;
  for r in select * from public.reward_rules rr where rr.active
             and rr.unit_id is not distinct from (case when exists (select 1 from public.reward_rules x where x.unit_id = p.unit_id) then p.unit_id else null end)
             and not exists (select 1 from public.reward_grants g where g.person_id = p_person_id and g.rule_id = rr.id)
           order by rr.threshold loop
    v_earned := case r.condition_type
      when 'step_completed' then coalesce(j.completed_steps, 0) >= r.threshold
      when 'milestone_days' then j.started_at is not null and now() >= j.started_at + make_interval(days => r.threshold) and coalesce(j.completed_steps, 0) > 0
      when 'points_threshold' then p.points >= r.threshold
      else false end;
    if not v_earned then continue; end if;
    select t.id into v_team from public.teams t where t.unit_id = p.unit_id and t.kind = 'logistics' and t.active
      and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
    if v_team is null then select t.id into v_team from public.teams t where t.unit_id = p.unit_id and t.kind = 'central'; end if;
    insert into public.referrals (unit_id, person_id, household_id, team_id, referral_type, reason, priority)
    values (p.unit_id, p_person_id, p.household_id, v_team, 'reward_delivery', 'premiação: ' || r.item || ' (' || r.name || ')', 2) returning id into v_ref;
    insert into public.referral_events (unit_id, referral_id, to_status, note) values (p.unit_id, v_ref, 'new', 'reward ' || r.key);
    insert into public.reward_grants (unit_id, person_id, rule_id, referral_id) values (p.unit_id, p_person_id, r.id, v_ref);
    insert into public.delivery_orders (unit_id, referral_id, person_id, household_id, kind, item_code, scheduled_for, address_snapshot)
    select p.unit_id, v_ref, p_person_id, p.household_id, 'reward', r.item, current_date + 3,
           jsonb_build_object('street', pc.street, 'number', pc.number, 'complement', pc.complement, 'postal_code', pc.postal_code, 'reference', pc.address_raw, 'kind', pc.address_kind)
    from public.people_contacts pc where pc.person_id = p_person_id;
    insert into public.person_events (unit_id, person_id, event_type, payload) values (p.unit_id, p_person_id, 'reward_earned', jsonb_build_object('rule', r.key, 'item', r.item));
    if r.stage_on_earn is not null then update public.people set stage = r.stage_on_earn where id = p_person_id and stage in ('journey_active', 'day7_done'); end if;
    if r.message_text is not null and p.phone_e164 is not null and exists (select 1 from public.consents c where c.person_id = p_person_id and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null) then
      insert into public.message_log (unit_id, person_id, to_phone_e164, kind, status, scheduled_for, payload)
      values (p.unit_id, p_person_id, p.phone_e164, 'text', 'queued', now(), jsonb_build_object('text', replace(r.message_text, '{{1}}', coalesce(p.first_name, ''))));
    end if;
    v_granted := v_granted + 1;
  end loop;
  return v_granted;
end $$;

-- Passo assistido: progresso, pontos, mensagem de progresso, pergunta "o que achou", marcos
create or replace function public.journey_mark_watched(p_person_id uuid, p_wamid text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare jp record; j record; v_total integer; v_phone text; v_unit uuid;
begin
  select * into j from public.person_journeys where person_id = p_person_id;
  if j.id is null then
    perform public.start_journey(p_person_id);
    select * into j from public.person_journeys where person_id = p_person_id;
  end if;
  select * into jp from public.journey_progress where person_id = p_person_id and status = 'sent' order by sequence desc limit 1;
  if jp.id is null then return jsonb_build_object('action', 'no_pending_step'); end if;
  update public.journey_progress set status = 'watched', watched_at = now() where id = jp.id;
  update public.person_journeys set completed_steps = completed_steps + 1 where id = j.id;
  perform public.add_points(p_person_id, 'video_watched', jp.id);
  select count(*) into v_total from public.journey_steps_for(j.unit_id, j.journey_key) s where s.question_kind is null;
  select pc.phone_e164 into v_phone from public.people_contacts pc where pc.person_id = p_person_id;
  select unit_id into v_unit from public.people where id = p_person_id;
  if v_phone is not null then
    insert into public.message_log (unit_id, person_id, to_phone_e164, kind, status, scheduled_for, payload)
    values (v_unit, p_person_id, v_phone, 'interactive', 'queued', now(),
            jsonb_build_object('text', format('Você completou %s de %s passos. O que achou deste vídeo?', j.completed_steps + 1, v_total),
                               'buttons', '[{"id":"fb_3","title":"Gostei muito"},{"id":"fb_2","title":"Mais ou menos"},{"id":"fb_1","title":"Não entendi"}]'::jsonb));
  end if;
  perform public.evaluate_rewards(p_person_id);
  return jsonb_build_object('action', 'video_watched', 'sequence', jp.sequence);
end $$;

create or replace function public.journey_feedback(p_person_id uuid, p_score smallint) returns void
language plpgsql security definer set search_path = public as $$
declare jp record; v_unit uuid;
begin
  select * into jp from public.journey_progress where person_id = p_person_id and status = 'watched' and feedback_score is null order by sequence desc limit 1;
  if jp.id is null then return; end if;
  update public.journey_progress set feedback_score = p_score, feedback_at = now() where id = jp.id;
  select unit_id into v_unit from public.people where id = p_person_id;
  insert into public.person_events (unit_id, person_id, event_type, payload) values (v_unit, p_person_id, 'feedback', jsonb_build_object('sequence', jp.sequence, 'score', p_score));
  perform public.add_points(p_person_id, 'feedback', jp.id);
end $$;

create or replace function public.journey_answer(p_person_id uuid, p_kind text, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
declare jp record; v_unit uuid; v_version text;
begin
  select unit_id, consent_text_version into v_unit, v_version from public.people where id = p_person_id;
  select jp2.* into jp from public.journey_progress jp2 join public.journey_steps s on s.id = jp2.step_id
  where jp2.person_id = p_person_id and s.question_kind = p_kind and jp2.status = 'sent' order by jp2.sequence desc limit 1;
  if jp.id is not null then update public.journey_progress set status = 'answered', answer = p_answer, watched_at = now() where id = jp.id; end if;
  if p_kind = 'income' then
    update public.people set income_range = p_answer,
      profile_segment = case when p_answer = 'over_3_mw' or occupation_area = 'autônomo/empresário' then 'business' when p_answer = 'up_to_1_mw' then 'support' else coalesce(profile_segment, 'general') end
    where id = p_person_id;
  elsif p_kind = 'events_optin' then
    insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via)
    values (v_unit, p_person_id, 'marketing_events', p_answer = 'yes', v_version, 'whatsapp_button')
    on conflict (person_id, purpose, consent_text_version) do update set revoked_at = case when excluded.granted then null else now() end, revoke_reason = case when excluded.granted then null else 'botão' end;
  elsif p_kind = 'church' then
    if p_answer = 'yes' then
      insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via)
      values (v_unit, p_person_id, 'share_with_church', true, v_version, 'whatsapp_button') on conflict do nothing;
      insert into public.person_events (unit_id, person_id, event_type, payload) values (v_unit, p_person_id, 'church_interest', '{"answer":"yes"}');
      insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority)
      select v_unit, p_person_id, coalesce(
        (select t.id from public.teams t where t.unit_id = v_unit and t.kind = 'follow_up' and t.active and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active)),
        (select t.id from public.teams t where t.unit_id = v_unit and t.kind = 'central')), 'church_connection', 'quer conhecer uma igreja', 2
      where not exists (select 1 from public.referrals r where r.person_id = p_person_id and r.referral_type = 'church_connection' and r.status not in ('done', 'cancelled'));
    elsif p_answer = 'have' then
      update public.people set attends_church = true where id = p_person_id;
    end if;
  end if;
  insert into public.person_events (unit_id, person_id, event_type, payload) values (v_unit, p_person_id, 'profile_answer', jsonb_build_object('kind', p_kind, 'answer', p_answer));
  perform public.add_points(p_person_id, 'profile_answer', jp.id);
end $$;

-- Avança jornadas vencidas (pg_cron a cada 15 min): enfileira o próximo passo como template
create or replace function public.advance_journeys() returns jsonb
language plpgsql security definer set search_path = public as $$
declare j record; s record; nxt record; p record; v_asset_id uuid; v_asset_url text; v_msg uuid; v_sent integer := 0; v_skipped integer := 0; v_completed integer := 0;
begin
  perform public.assert_service_role();
  for j in select * from public.person_journeys pj where pj.status = 'active' and pj.next_send_at is not null and pj.next_send_at <= now() order by pj.next_send_at limit 500 loop
    select pe.stage, pe.unit_id, pe.profile_segment, pc.phone_e164, split_part(pc.full_name, ' ', 1) as first_name into p
    from public.people pe left join public.people_contacts pc on pc.person_id = pe.id where pe.id = j.person_id;
    if p.stage in ('opted_out', 'anonymized') or p.phone_e164 is null then
      update public.person_journeys set status = 'stopped', next_send_at = null where id = j.id; continue;
    end if;
    if p.stage in ('paused', 'inactive') then
      update public.person_journeys set status = 'paused', next_send_at = null where id = j.id; continue;
    end if;
    if not exists (select 1 from public.consents c where c.person_id = j.person_id and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null) then
      update public.person_journeys set status = 'stopped', next_send_at = null where id = j.id; continue;
    end if;
    select * into s from public.journey_steps_for(j.unit_id, j.journey_key) x
    where x.sequence > j.current_sequence and (x.audience_segment is null or x.audience_segment = p.profile_segment) order by x.sequence limit 1;
    if s.id is null then
      update public.person_journeys set status = 'completed', next_send_at = null where id = j.id; v_completed := v_completed + 1; continue;
    end if;
    v_asset_id := null; v_asset_url := null;
    if s.content_key is not null then
      select ca.id, ca.public_url into v_asset_id, v_asset_url from public.content_assets ca where ca.key = s.content_key and ca.active and ca.rights_ok and (ca.unit_id = j.unit_id or ca.unit_id is null) order by ca.unit_id nulls last limit 1;
    end if;
    if s.content_key is not null and v_asset_id is null then
      insert into public.journey_progress (unit_id, person_id, step_id, sequence, status) values (j.unit_id, j.person_id, s.id, s.sequence, 'skipped') on conflict do nothing;
      insert into public.person_events (unit_id, person_id, event_type, payload) values (j.unit_id, j.person_id, 'journey_step_skipped', jsonb_build_object('sequence', s.sequence, 'reason', 'no_asset'));
      v_skipped := v_skipped + 1;
    else
      insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, content_asset_id, status, scheduled_for, payload)
      values (j.unit_id, j.person_id, p.phone_e164, 'template', s.template_name, v_asset_id, 'queued', public.next_send_slot(j.unit_id, now()),
              jsonb_build_object('first_name', coalesce(p.first_name, ''), 'body_params', case when s.question_kind is null then jsonb_build_array(coalesce(p.first_name, ''), s.title) else jsonb_build_array(coalesce(p.first_name, '')) end,
                                 'header_video_link', v_asset_url, 'journey_sequence', s.sequence))
      returning id into v_msg;
      insert into public.journey_progress (unit_id, person_id, step_id, sequence, status, message_log_id, sent_at)
      values (j.unit_id, j.person_id, s.id, s.sequence, 'sent', v_msg, now()) on conflict do nothing;
      insert into public.person_events (unit_id, person_id, event_type, payload) values (j.unit_id, j.person_id, 'journey_step_sent', jsonb_build_object('sequence', s.sequence, 'title', s.title));
      v_sent := v_sent + 1;
    end if;
    select * into nxt from public.journey_steps_for(j.unit_id, j.journey_key) x where x.sequence > s.sequence and (x.audience_segment is null or x.audience_segment = p.profile_segment) order by x.sequence limit 1;
    update public.person_journeys set current_sequence = s.sequence, last_step_sent_at = now(),
      next_send_at = case when nxt.id is not null then public.next_send_slot(j.unit_id, greatest(j.started_at + make_interval(days => nxt.day_offset), now() + interval '1 day')) end,
      status = case when nxt.id is null then 'completed' else status end
    where id = j.id;
  end loop;
  return jsonb_build_object('sent', v_sent, 'skipped', v_skipped, 'completed', v_completed);
end $$;

-- confirm_optin agora inicia a jornada
create or replace function public.confirm_optin(p_unit_id uuid, p_person_id uuid, p_wamid text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.assert_service_role();
  update public.consents set confirmed_at = coalesce(confirmed_at, now()), confirmation_wamid = coalesce(confirmation_wamid, p_wamid)
  where person_id = p_person_id and purpose = 'whatsapp_contact' and granted and revoked_at is null;
  update public.people set stage = 'journey_active', optin_confirmed_at = coalesce(optin_confirmed_at, now()), last_contact_at = now()
  where id = p_person_id and unit_id = p_unit_id and stage in ('registered', 'first_contact_pending', 'paused', 'inactive');
  insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, p_person_id, 'optin_confirmed', jsonb_build_object('wamid', p_wamid));
  perform public.start_journey(p_person_id);
end $$;

-- ---------------------------------------------------------------------------
-- Botões: jornada, perguntas, feedback, opt-in, parar (usado por handle_inbound)
-- ---------------------------------------------------------------------------
create or replace function public.handle_button(p_unit_id uuid, p_person_id uuid, p_phone_e164 text, p_button text, p_wamid text) returns text
language plpgsql security definer set search_path = public as $$
declare v_stage text;
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

create or replace function public.handle_inbound(p_unit_id uuid, p_wa_id text, p_phone_e164 text, p_kind text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_person uuid; v_text text; v_norm text; v_team uuid; v_ref uuid; v_wamid text; v_action text := 'none';
begin
  perform public.assert_service_role();
  v_wamid := p_payload->>'wamid';
  v_person := public.resolve_person_by_wa(p_unit_id, p_wa_id, p_phone_e164);
  if v_person is null then return jsonb_build_object('action', 'unknown_sender'); end if;
  update public.people_contacts set wa_id = coalesce(wa_id, p_wa_id) where person_id = v_person;
  update public.people set last_contact_at = now() where id = v_person;

  if p_kind = 'button' then
    v_action := public.handle_button(p_unit_id, v_person, p_phone_e164, p_payload->>'button_id', v_wamid);
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
      select t.id into v_team from public.teams t where t.unit_id = p_unit_id and t.kind = 'follow_up' and t.active
        and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
      if v_team is null then select t.id into v_team from public.teams t where t.unit_id = p_unit_id and t.kind = 'central'; end if;
      if not exists (select 1 from public.referrals r where r.person_id = v_person and r.referral_type = 'follow_up' and r.status not in ('done', 'cancelled')) then
        insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority)
        values (p_unit_id, v_person, v_team, 'follow_up', 'mensagem no WhatsApp: ' || left(v_text, 80), 1) returning id into v_ref;
        insert into public.referral_events (unit_id, referral_id, to_status, note) values (p_unit_id, v_ref, 'new', 'inbound');
        insert into public.notifications (unit_id, team_id, kind, title, ref_table, ref_id) values (p_unit_id, v_team, 'referral', 'Mensagem recebida no WhatsApp', 'referrals', v_ref);
      end if;
      insert into public.person_events (unit_id, person_id, event_type, payload) values (p_unit_id, v_person, 'note', jsonb_build_object('wamid', v_wamid, 'inbound_text', left(v_text, 500)));
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
-- CRM: anotações de acompanhamento e responsável
-- ---------------------------------------------------------------------------
create or replace function public.add_follow_up(p_person_id uuid, p_note text, p_channel text default 'whatsapp', p_next_action_at timestamptz default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_id uuid;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  if v_unit is null then raise exception 'person_not_found'; end if;
  if not (public.can_write_unit(v_unit) or (public.auth_role() = 'team_member' and exists (
      select 1 from public.referrals r where r.person_id = p_person_id and r.team_id = any (public.auth_team_ids())))) then
    raise insufficient_privilege;
  end if;
  insert into public.follow_ups (unit_id, person_id, member_id, channel, note, next_action_at) values (v_unit, p_person_id, auth.uid(), p_channel, p_note, p_next_action_at) returning id into v_id;
  update public.people set last_contact_at = now(), assigned_to = coalesce(assigned_to, auth.uid()) where id = p_person_id;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, p_person_id, 'follow_up', auth.uid(), jsonb_build_object('channel', p_channel, 'note', left(p_note, 200)));
  -- fecha o encaminhamento de acompanhamento aberto (contato humano feito)
  update public.referrals set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), assigned_to = coalesce(assigned_to, auth.uid())
  where person_id = p_person_id and referral_type = 'follow_up' and status = 'new';
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Logística
-- ---------------------------------------------------------------------------
create or replace function public.start_assistance_program(p_referral_id uuid, p_months integer default null, p_frequency_days integer default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare r record; u record; v_months integer; v_freq integer; v_id uuid; i integer; v_snapshot jsonb;
begin
  select * into r from public.referrals where id = p_referral_id and referral_type = 'basic_food';
  if r.id is null then raise exception 'referral_not_found'; end if;
  if not (public.can_write_unit(r.unit_id) or (public.auth_role() = 'team_member' and r.team_id = any (public.auth_team_ids()))) then raise insufficient_privilege; end if;
  select settings into u from public.units where id = r.unit_id;
  v_months := coalesce(p_months, (u.settings->>'basic_food_months')::int, 3);
  v_freq := coalesce(p_frequency_days, (u.settings->>'basic_food_frequency_days')::int, 30);
  if r.household_id is not null and exists (select 1 from public.assistance_programs ap where ap.household_id = r.household_id and ap.program_type = 'basic_food' and ap.status = 'active') then
    raise exception 'program_already_active_for_household';
  end if;
  select jsonb_build_object('street', pc.street, 'number', pc.number, 'complement', pc.complement, 'postal_code', pc.postal_code, 'reference', pc.address_raw, 'kind', pc.address_kind, 'phone', pc.phone_e164)
    into v_snapshot from public.people_contacts pc where pc.person_id = r.person_id;
  insert into public.assistance_programs (unit_id, household_id, person_id, referral_id, program_type, start_date, end_date, planned_deliveries, created_by)
  values (r.unit_id, r.household_id, r.person_id, r.id, 'basic_food', current_date, current_date + make_interval(months => v_months)::interval, greatest(1, (v_months * 30) / v_freq), auth.uid())
  returning id into v_id;
  for i in 0 .. greatest(1, (v_months * 30) / v_freq) - 1 loop
    insert into public.delivery_orders (unit_id, program_id, referral_id, person_id, household_id, kind, scheduled_for, address_snapshot)
    values (r.unit_id, v_id, r.id, r.person_id, r.household_id, 'basic_food', current_date + (i * v_freq), v_snapshot);
  end loop;
  if r.status in ('new', 'triaged') then perform public.referral_transition(r.id, 'in_progress', 'programa de ' || v_months || ' meses iniciado'); end if;
  return v_id;
end $$;

create or replace function public.delivery_transition(p_delivery_id uuid, p_to text, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare d record; v_ok boolean; v_phone text; v_first text; v_status_text text; v_prog record;
begin
  select * into d from public.delivery_orders where id = p_delivery_id;
  if d.id is null then raise exception 'delivery_not_found'; end if;
  v_ok := public.can_write_unit(d.unit_id) or (public.auth_role() = 'team_member' and exists (
    select 1 from public.team_members tm join public.teams t on t.id = tm.team_id where tm.profile_id = auth.uid() and tm.active and t.unit_id = d.unit_id and t.kind in ('logistics', 'basic_food', 'home_items')));
  if not v_ok then raise insufficient_privilege; end if;
  if not (
    (d.status = 'scheduled' and p_to in ('picking', 'packed', 'out_for_delivery', 'cancelled')) or
    (d.status = 'picking' and p_to in ('packed', 'cancelled')) or
    (d.status = 'packed' and p_to in ('out_for_delivery', 'cancelled')) or
    (d.status = 'out_for_delivery' and p_to in ('delivered', 'failed')) or
    (d.status = 'failed' and p_to in ('scheduled', 'out_for_delivery', 'cancelled'))) then
    raise exception 'invalid_transition % -> %', d.status, p_to;
  end if;
  update public.delivery_orders set status = p_to,
    dispatched_at = case when p_to = 'out_for_delivery' then now() else dispatched_at end,
    delivered_at = case when p_to = 'delivered' then now() else delivered_at end,
    driver_id = case when p_to = 'out_for_delivery' then coalesce(driver_id, auth.uid()) else driver_id end,
    proof_note = case when p_to = 'delivered' then coalesce(p_note, proof_note) else proof_note end,
    failure_reason = case when p_to = 'failed' then coalesce(p_note, failure_reason) else failure_reason end
  where id = p_delivery_id;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload)
  values (d.unit_id, d.person_id, 'delivery_status', auth.uid(), jsonb_build_object('delivery_id', d.id, 'kind', d.kind, 'status', p_to, 'note', p_note));
  -- aviso à pessoa (UTILITY) só com consentimento social + whatsapp
  if p_to in ('out_for_delivery', 'delivered') then
    select pc.phone_e164, split_part(pc.full_name, ' ', 1) into v_phone, v_first from public.people_contacts pc where pc.person_id = d.person_id;
    if v_phone is not null and exists (select 1 from public.consents c where c.person_id = d.person_id and c.purpose = 'whatsapp_contact' and c.granted and c.revoked_at is null)
       and (d.kind = 'reward' or exists (select 1 from public.consents c where c.person_id = d.person_id and c.purpose = 'social_assistance' and c.granted and c.revoked_at is null)) then
      v_status_text := case p_to when 'out_for_delivery' then 'sua ' || case d.kind when 'basic_food' then 'cesta básica' when 'reward' then 'premiação' else 'entrega' end || ' saiu para entrega hoje.'
                                 else 'sua ' || case d.kind when 'basic_food' then 'cesta básica' when 'reward' then 'premiação' else 'entrega' end || ' foi entregue. Deus abençoe!' end;
      insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, status, scheduled_for, payload, pricing_category)
      values (d.unit_id, d.person_id, v_phone, 'template', 'transtornar_entrega_v1', 'queued', public.next_send_slot(d.unit_id, now()),
              jsonb_build_object('first_name', v_first, 'body_params', jsonb_build_array(v_first, v_status_text)), 'utility');
    end if;
  end if;
  if p_to = 'delivered' then
    if d.program_id is not null then
      update public.assistance_programs set completed_deliveries = completed_deliveries + 1 where id = d.program_id returning * into v_prog;
      if v_prog.completed_deliveries >= v_prog.planned_deliveries then
        update public.assistance_programs set status = 'completed' where id = v_prog.id;
        if v_prog.referral_id is not null then
          update public.referrals set status = 'done', done_at = now(), outcome = 'programa concluído' where id = v_prog.referral_id and status not in ('done', 'cancelled');
        end if;
      end if;
    elsif d.kind = 'reward' then
      update public.reward_grants set delivered_at = now() where referral_id = d.referral_id;
      update public.referrals set status = 'done', done_at = now(), outcome = 'entregue' where id = d.referral_id and status not in ('done', 'cancelled');
      insert into public.person_events (unit_id, person_id, event_type, payload) values (d.unit_id, d.person_id, 'reward_delivered', jsonb_build_object('item', d.item_code));
    elsif d.referral_id is not null then
      update public.referrals set status = 'done', done_at = now(), outcome = 'entregue' where id = d.referral_id and status not in ('done', 'cancelled');
    end if;
  end if;
end $$;

create or replace view public.v_delivery_kpi with (security_invoker = true) as
  select unit_id,
         count(*) filter (where status = 'delivered') as delivered,
         count(*) filter (where status = 'failed') as failed,
         count(*) filter (where status in ('scheduled', 'picking', 'packed', 'out_for_delivery')) as open,
         round(100.0 * count(*) filter (where status = 'delivered' and delivered_at::date = created_at::date) / nullif(count(*) filter (where status = 'delivered'), 0), 1) as same_day_pct,
         round(avg(extract(epoch from (delivered_at - created_at)) / 3600) filter (where status = 'delivered'), 1) as avg_lead_hours
  from public.delivery_orders group by unit_id;

-- ---------------------------------------------------------------------------
-- Mesclagem de duplicatas
-- ---------------------------------------------------------------------------
create or replace function public.merge_people(p_duplicate uuid, p_primary uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid;
begin
  select unit_id into v_unit from public.people where id = p_duplicate;
  if v_unit is null or p_duplicate = p_primary or v_unit <> (select unit_id from public.people where id = p_primary) then raise exception 'invalid_merge'; end if;
  if not public.can_write_unit(v_unit) then raise insufficient_privilege; end if;
  update public.needs set person_id = p_primary where person_id = p_duplicate;
  update public.referrals set person_id = p_primary where person_id = p_duplicate and status not in ('done', 'cancelled');
  update public.follow_ups set person_id = p_primary where person_id = p_duplicate;
  update public.delivery_orders set person_id = p_primary where person_id = p_duplicate;
  update public.assistance_programs set person_id = p_primary where person_id = p_duplicate;
  insert into public.children (unit_id, person_id, age_band) select unit_id, p_primary, age_band from public.children where person_id = p_duplicate
    and not exists (select 1 from public.children where person_id = p_primary);
  update public.people set review_status = 'merged', duplicate_of_person_id = p_primary where id = p_duplicate;
  perform public.anonymize_person(p_duplicate, 'merged');
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, p_primary, 'merged', auth.uid(), jsonb_build_object('merged_from', p_duplicate));
  perform public.apply_routing_rules(p_primary);
end $$;

-- ---------------------------------------------------------------------------
-- Retenção v2: "Agora não" + 90 dias sem interação => inativo + contato humano (nunca anonimização)
-- ---------------------------------------------------------------------------
create or replace function public.run_retention_policy() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_inactive integer := 0; v_anon integer := 0; r record; v_team uuid;
begin
  perform public.assert_service_role();
  for r in select pe.id, pe.unit_id from public.people pe
           where (pe.stage = 'first_contact_pending' and pe.first_contact_sent_at < now() - interval '16 days' and pe.last_contact_at is null)
              or (pe.stage = 'paused' and coalesce(pe.last_contact_at, pe.stage_changed_at) < now() - interval '90 days') loop
    update public.people set stage = 'inactive' where id = r.id;
    select t.id into v_team from public.teams t where t.unit_id = r.unit_id and t.kind = 'follow_up' and t.active
      and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
    if v_team is null then select t.id into v_team from public.teams t where t.unit_id = r.unit_id and t.kind = 'central'; end if;
    if not exists (select 1 from public.referrals x where x.person_id = r.id and x.referral_type = 'follow_up' and x.status not in ('done', 'cancelled')) then
      insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority) values (r.unit_id, r.id, v_team, 'follow_up', 'sem resposta no WhatsApp: contato humano', 2);
    end if;
    insert into public.person_events (unit_id, person_id, event_type, payload) values (r.unit_id, r.id, 'contact_attempt', '{"channel":"whatsapp","result":"no_response"}');
    v_inactive := v_inactive + 1;
  end loop;
  for r in select pe.id from public.people pe where pe.stage = 'opted_out' and pe.stage_changed_at < now() - interval '30 days' loop
    perform public.anonymize_person(r.id, 'opted_out'); v_anon := v_anon + 1;
  end loop;
  delete from public.wa_inbound_events where created_at < now() - interval '90 days';
  return jsonb_build_object('inactivated', v_inactive, 'anonymized', v_anon);
end $$;

-- anonymize_person também limpa as tabelas novas
create or replace function public.anonymize_person_extra(p_person_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.follow_ups set note = '[anonimizado]' where person_id = p_person_id;
  update public.delivery_orders set address_snapshot = null, proof_note = null where person_id = p_person_id;
  update public.journey_progress set answer = null where person_id = p_person_id;
  update public.people set income_range = null, case_summary = null where id = p_person_id;
end $$;
create or replace function public.anonymize_person_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.stage = 'anonymized' and old.stage is distinct from 'anonymized' then perform public.anonymize_person_extra(new.id); end if;
  return new;
end $$;
create trigger people_anonymize_extra after update of stage on public.people for each row execute function public.anonymize_person_after();

-- ---------------------------------------------------------------------------
-- Jobs, Realtime, grants e RLS
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('journey-tick', '*/15 * * * *', $c$ select public.advance_journeys() $c$);
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.people, public.referrals, public.notifications, public.delivery_orders;
  end if;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.register_person(jsonb), public.record_decision_tally(uuid, boolean), public.referral_transition(uuid, text, text),
  public.mark_duplicate(uuid, uuid), public.confirm_distinct_person(uuid), public.open_person_record(uuid), public.get_my_registrations(),
  public.get_team_queue(text), public.anonymize_person(uuid, text), public.create_invite(text, text, uuid), public.accept_invite(text),
  public.clone_unit_defaults(uuid), public.auth_unit_id(), public.auth_role(), public.auth_team_ids(), public.is_unit_staff(),
  public.can_read_unit(uuid), public.can_write_unit(uuid), public.normalize_text(text), public.normalize_e164(text), public.find_neighborhood(uuid, text),
  public.add_follow_up(uuid, text, text, timestamptz), public.start_assistance_program(uuid, integer, integer), public.delivery_transition(uuid, text, text),
  public.merge_people(uuid, uuid)
  to authenticated;
grant execute on function public.get_invite(text), public.normalize_text(text) to anon;
grant execute on all functions in schema public to service_role;

alter table public.journey_steps enable row level security;
alter table public.person_journeys enable row level security;
alter table public.journey_progress enable row level security;
alter table public.reward_rules enable row level security;
alter table public.reward_grants enable row level security;
alter table public.point_rules enable row level security;
alter table public.points_ledger enable row level security;
alter table public.follow_ups enable row level security;
alter table public.assistance_programs enable row level security;
alter table public.delivery_orders enable row level security;

create policy journey_steps_select on public.journey_steps for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy journey_steps_write on public.journey_steps for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy reward_rules_select on public.reward_rules for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy reward_rules_write on public.reward_rules for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy point_rules_select on public.point_rules for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy point_rules_write on public.point_rules for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy person_journeys_staff on public.person_journeys for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy journey_progress_staff on public.journey_progress for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy reward_grants_staff on public.reward_grants for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy points_ledger_staff on public.points_ledger for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy follow_ups_select on public.follow_ups for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or member_id = auth.uid());
create policy follow_ups_update on public.follow_ups for update to authenticated using (public.can_write_unit(unit_id) or member_id = auth.uid());
create policy assistance_programs_select on public.assistance_programs for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or exists (select 1 from public.referrals r where r.id = referral_id and r.team_id = any (public.auth_team_ids())));
create policy assistance_programs_write on public.assistance_programs for update to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy delivery_orders_select on public.delivery_orders for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or driver_id = auth.uid() or exists (
    select 1 from public.team_members tm join public.teams t on t.id = tm.team_id where tm.profile_id = auth.uid() and tm.active and t.unit_id = delivery_orders.unit_id and t.kind in ('logistics', 'basic_food', 'home_items')));
create policy delivery_orders_write on public.delivery_orders for update to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));

-- Ficha completa (inclui jornada, acompanhamento, programa, entregas, prêmios)
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
    'assigned_name', (select pr.full_name from public.profiles pr where pr.id = pe.assigned_to),
    'children', (select coalesce(jsonb_agg(to_jsonb(c) order by c.age_band), '[]') from public.children c where c.person_id = pe.id),
    'needs', (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at), '[]') from public.needs n where n.person_id = pe.id),
    'consents', (select coalesce(jsonb_agg(to_jsonb(co) order by co.granted_at), '[]') from public.consents co where co.person_id = pe.id),
    'referrals', (select coalesce(jsonb_agg((to_jsonb(r) || jsonb_build_object('team_kind', t.kind, 'team_name', t.name)) order by r.created_at), '[]')
                  from public.referrals r join public.teams t on t.id = r.team_id where r.person_id = pe.id),
    'journey', (select to_jsonb(pj) from public.person_journeys pj where pj.person_id = pe.id),
    'journey_progress', (select coalesce(jsonb_agg((to_jsonb(jp) || jsonb_build_object('title', s.title)) order by jp.sequence), '[]')
                         from public.journey_progress jp join public.journey_steps s on s.id = jp.step_id where jp.person_id = pe.id),
    'rewards', (select coalesce(jsonb_agg(jsonb_build_object('item', rr.item, 'name', rr.name, 'earned_at', g.earned_at, 'delivered_at', g.delivered_at) order by g.earned_at), '[]')
                from public.reward_grants g join public.reward_rules rr on rr.id = g.rule_id where g.person_id = pe.id),
    'follow_ups', (select coalesce(jsonb_agg((to_jsonb(f) || jsonb_build_object('member_name', pr.full_name)) order by f.created_at desc), '[]')
                   from public.follow_ups f left join public.profiles pr on pr.id = f.member_id where f.person_id = pe.id),
    'programs', (select coalesce(jsonb_agg(to_jsonb(ap) order by ap.created_at desc), '[]') from public.assistance_programs ap where ap.person_id = pe.id),
    'deliveries', (select coalesce(jsonb_agg(to_jsonb(d) order by d.scheduled_for), '[]') from public.delivery_orders d where d.person_id = pe.id),
    'events', (select coalesce(jsonb_agg(to_jsonb(ev) order by ev.occurred_at desc), '[]') from public.person_events ev where ev.person_id = pe.id),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'template_name', m.template_name, 'status', m.status,
                   'skip_reason', m.skip_reason, 'error_code', m.error_code, 'scheduled_for', m.scheduled_for, 'sent_at', m.sent_at,
                   'delivered_at', m.delivered_at, 'read_at', m.read_at) order by m.created_at desc), '[]')
                 from public.message_log m where m.person_id = pe.id)
  ) into result
  from public.people pe where pe.id = p_person_id;
  return result;
end $$;
