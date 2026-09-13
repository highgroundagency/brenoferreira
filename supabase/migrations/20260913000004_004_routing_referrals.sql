-- 004 — regras de roteamento, encaminhamentos (filas por time), notificações e o motor apply_routing_rules

create table public.routing_rules (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),        -- null = regra global (padrão clonável)
  name text not null,
  priority integer not null,
  condition jsonb not null,
  target_team_kind text not null,
  referral_type text not null check (referral_type in
    ('basic_food', 'home_items', 'education', 'employment', 'follow_up', 'strategy_review', 'reward_delivery', 'church_connection', 'other')),
  auto_triage boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index routing_rules_unit_priority_idx on public.routing_rules (unit_id, priority) where active;
create trigger routing_rules_set_updated_at before update on public.routing_rules for each row execute function public.set_updated_at();

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  household_id uuid references public.households(id),
  need_id uuid references public.needs(id) on delete set null,
  child_id uuid references public.children(id) on delete set null,
  team_id uuid not null references public.teams(id),
  referral_type text not null check (referral_type in
    ('basic_food', 'home_items', 'education', 'employment', 'follow_up', 'strategy_review', 'reward_delivery', 'church_connection', 'other')),
  rule_id uuid references public.routing_rules(id),
  reason text,
  priority smallint not null default 2 check (priority between 1 and 3),
  status text not null default 'new' check (status in ('new', 'triaged', 'in_progress', 'waiting', 'done', 'cancelled')),
  flags text[] not null default '{}',
  assigned_to uuid references public.profiles(id),
  assigned_at timestamptz,
  first_response_at timestamptz,
  done_at timestamptz,
  outcome text,
  cancelled_reason text,
  parent_id uuid references public.referrals(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index referrals_queue_idx on public.referrals (unit_id, team_id, status, created_at);
create index referrals_person_idx on public.referrals (person_id);
create trigger referrals_set_updated_at before update on public.referrals for each row execute function public.set_updated_at();

create table public.referral_events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  referral_id uuid not null references public.referrals(id) on delete cascade,
  from_status text,
  to_status text not null,
  actor_profile_id uuid references public.profiles(id),
  note text,
  created_at timestamptz not null default now()
);
create index referral_events_referral_idx on public.referral_events (referral_id, created_at);
create trigger referral_events_append_only before update or delete on public.referral_events for each row execute function public.reject_change();

-- Notificações: para um time (título sem PII) ou para um perfil da central (título com primeiro nome)
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  recipient_profile_id uuid references public.profiles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  kind text not null,
  title text not null,
  ref_table text,
  ref_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_target_chk check (recipient_profile_id is not null or team_id is not null)
);
create index notifications_recipient_idx on public.notifications (recipient_profile_id, created_at desc) where read_at is null;
create index notifications_team_idx on public.notifications (team_id, created_at desc) where read_at is null;

create or replace function public.need_type_label(p text) returns text
language sql immutable as $$
  select case p
    when 'food' then 'alimento' when 'furniture' then 'móvel' when 'appliance' then 'eletrodoméstico'
    when 'clothing' then 'roupas' when 'health' then 'saúde' when 'job' then 'trabalho'
    when 'training' then 'curso' else 'outro' end
$$;

-- ---------------------------------------------------------------------------
-- Motor de roteamento (idempotente): chamado por register_person e pelo trigger needs_route.
-- Condições suportadas em routing_rules.condition:
--   {"always": true}
--   {"need_type": "food"} | {"need_type_in": ["furniture","appliance"]}   -> um referral por necessidade aberta
--   {"children_age_band_in": ["12_14","15_17"]}                            -> um referral por pessoa
--   {"person_flags_any": ["needs_job","wants_training"]}                   -> um referral por pessoa
-- Time inativo ou sem membro ativo -> central (fallback_to_central). Retorna quantos referrals criou.
-- ---------------------------------------------------------------------------
create or replace function public.apply_routing_rules(p_person_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  p record;
  r record;
  n record;
  v_central_team uuid;
  v_target_team uuid;
  v_created integer := 0;
  v_first_name text;
  v_nbh text;
  v_flags text[];
  v_reason text;
  v_need_id uuid;
  v_labels text;
  v_matches boolean;
  v_referral_id uuid;
  staff record;
begin
  select pe.*, pc.full_name into p
  from public.people pe left join public.people_contacts pc on pc.person_id = pe.id
  where pe.id = p_person_id;
  if not found or p.stage in ('anonymized', 'opted_out') then
    return 0;
  end if;

  select t.id into v_central_team from public.teams t where t.unit_id = p.unit_id and t.kind = 'central';
  v_first_name := split_part(coalesce(p.full_name, ''), ' ', 1);
  select nb.name into v_nbh from public.neighborhoods nb where nb.id = p.neighborhood_id;
  select string_agg(distinct public.need_type_label(ne.need_type), ', ') into v_labels
  from public.needs ne where ne.person_id = p.id and ne.status not in ('fulfilled', 'cancelled');

  for r in
    select * from public.routing_rules rr
    where rr.active and rr.unit_id is not distinct from (
      case when exists (select 1 from public.routing_rules x where x.unit_id = p.unit_id) then p.unit_id else null end)
    order by rr.priority, rr.created_at
  loop
    -- time alvo (fallback central)
    select t.id into v_target_team from public.teams t
    where t.unit_id = p.unit_id and t.kind = r.target_team_kind and t.active
      and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
    if v_target_team is null then
      select t.id into v_target_team from public.teams t
      where t.unit_id = p.unit_id and t.kind = r.target_team_kind and t.active
        and not exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active)
        and not t.fallback_to_central;
    end if;
    if v_target_team is null then
      v_target_team := v_central_team;
    end if;
    if v_target_team is null then
      continue;   -- unidade sem central: nada a fazer
    end if;

    if r.condition ? 'need_type' or r.condition ? 'need_type_in' then
      for n in
        select ne.* from public.needs ne
        where ne.person_id = p.id and ne.status not in ('fulfilled', 'cancelled')
          and (
            (r.condition ? 'need_type' and ne.need_type = r.condition->>'need_type')
            or (r.condition ? 'need_type_in' and ne.need_type in (select jsonb_array_elements_text(r.condition->'need_type_in')))
          )
      loop
        if exists (select 1 from public.referrals x where x.person_id = p.id and x.referral_type = r.referral_type
                   and x.need_id = n.id and x.status not in ('done', 'cancelled')) then
          continue;
        end if;
        v_flags := '{}';
        if r.referral_type = 'basic_food' and p.household_id is not null and exists (
          select 1 from public.referrals x where x.household_id = p.household_id and x.person_id <> p.id
            and x.referral_type = 'basic_food' and x.status not in ('done', 'cancelled')) then
          v_flags := array_append(v_flags, 'duplicate_household');
        end if;
        v_reason := public.need_type_label(n.need_type) || coalesce(' (' || n.item_code || ')', '');
        insert into public.referrals (unit_id, person_id, household_id, need_id, team_id, referral_type, rule_id, reason, priority, flags)
        values (p.unit_id, p.id, p.household_id, n.id, v_target_team, r.referral_type, r.id, v_reason,
                case when r.referral_type = 'basic_food' then 1 else 2 end, v_flags)
        returning id into v_referral_id;
        update public.needs set status = 'routed' where id = n.id and status = 'open';
        insert into public.referral_events (unit_id, referral_id, from_status, to_status, note) values (p.unit_id, v_referral_id, null, 'new', r.name);
        insert into public.person_events (unit_id, person_id, event_type, payload)
        values (p.unit_id, p.id, 'referral_created', jsonb_build_object('referral_id', v_referral_id, 'type', r.referral_type));
        insert into public.notifications (unit_id, team_id, kind, title, ref_table, ref_id)
        values (p.unit_id, v_target_team, 'referral', 'Nova pessoa no ' || coalesce(v_nbh, '?') || ' — ' || v_reason, 'referrals', v_referral_id);
        v_created := v_created + 1;
      end loop;
    else
      v_matches := false;
      v_need_id := null;
      if coalesce((r.condition->>'always')::boolean, false) then
        v_matches := true;
        v_reason := 'novo cadastro';
      elsif r.condition ? 'children_age_band_in' then
        select string_agg(replace(c.age_band, '_', '-'), ', ' order by c.age_band) into v_reason
        from public.children c where c.person_id = p.id
          and c.age_band in (select jsonb_array_elements_text(r.condition->'children_age_band_in'));
        v_matches := v_reason is not null;
        v_reason := 'filhos: ' || coalesce(v_reason, '');
      elsif r.condition ? 'person_flags_any' then
        v_matches := (r.condition->'person_flags_any' ? 'needs_job' and coalesce(p.needs_job, false))
                  or (r.condition->'person_flags_any' ? 'wants_training' and coalesce(p.wants_training, false));
        v_reason := concat_ws(', ', case when coalesce(p.needs_job, false) then 'precisa de trabalho' end,
                                    case when coalesce(p.wants_training, false) then 'quer curso' end,
                                    nullif(p.occupation_area, ''));
      end if;
      if not v_matches then
        continue;
      end if;
      if exists (select 1 from public.referrals x where x.person_id = p.id and x.referral_type = r.referral_type
                 and x.need_id is null and x.status not in ('done', 'cancelled')) then
        continue;
      end if;
      insert into public.referrals (unit_id, person_id, household_id, team_id, referral_type, rule_id, reason, priority)
      values (p.unit_id, p.id, p.household_id, v_target_team, r.referral_type, r.id, v_reason, case when r.referral_type = 'follow_up' then 1 else 3 end)
      returning id into v_referral_id;
      insert into public.referral_events (unit_id, referral_id, from_status, to_status, note) values (p.unit_id, v_referral_id, null, 'new', r.name);
      insert into public.person_events (unit_id, person_id, event_type, payload)
      values (p.unit_id, p.id, 'referral_created', jsonb_build_object('referral_id', v_referral_id, 'type', r.referral_type));
      if r.referral_type <> 'strategy_review' then
        insert into public.notifications (unit_id, team_id, kind, title, ref_table, ref_id)
        values (p.unit_id, v_target_team, 'referral', 'Nova pessoa no ' || coalesce(v_nbh, '?') || ' — ' || v_reason, 'referrals', v_referral_id);
      end if;
      v_created := v_created + 1;
    end if;
  end loop;

  -- Aviso à central (com primeiro nome: central/unit_admin já leem a ficha) — uma vez por cadastro
  if v_created > 0 and not exists (
      select 1 from public.notifications no where no.ref_table = 'people' and no.ref_id = p.id) then
    for staff in
      select pr.id from public.profiles pr where pr.unit_id = p.unit_id and pr.active and pr.role in ('central', 'unit_admin')
    loop
      insert into public.notifications (unit_id, recipient_profile_id, kind, title, ref_table, ref_id)
      values (p.unit_id, staff.id, 'person_registered',
              coalesce(nullif(v_first_name, ''), 'Nova pessoa') || ' — ' || coalesce(v_nbh, '?') || coalesce(' — ' || v_labels, ''),
              'people', p.id);
    end loop;
  end if;

  return v_created;
end $$;
revoke execute on function public.apply_routing_rules(uuid) from public;
grant execute on function public.apply_routing_rules(uuid) to service_role;

-- Nova necessidade registrada pela central (ou pelo webhook) => reexecuta o roteamento
create or replace function public.needs_route() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('app.skip_routing', true), '') <> 'on' then
    perform public.apply_routing_rules(new.person_id);
  end if;
  return new;
end $$;
create trigger needs_route after insert on public.needs for each row execute function public.needs_route();

-- Regras globais (unit_id null); times inativos caem na central
insert into public.routing_rules (unit_id, name, priority, condition, target_team_kind, referral_type, auto_triage, active) values
  (null, 'Estratégia recebe todo cadastro', 5, '{"always": true}', 'strategy', 'strategy_review', true, true),
  (null, 'Alimento -> cesta básica', 10, '{"need_type": "food"}', 'basic_food', 'basic_food', true, true),
  (null, 'Móveis e eletrodomésticos -> itens de casa', 20, '{"need_type_in": ["furniture", "appliance"]}', 'home_items', 'home_items', false, true),
  (null, 'Filhos adolescentes -> educação', 30, '{"children_age_band_in": ["12_14", "15_17"]}', 'education', 'education', false, true),
  (null, 'Trabalho ou curso -> emprego', 40, '{"person_flags_any": ["needs_job", "wants_training"]}', 'employment', 'employment', false, true),
  (null, 'Mensagem livre no WhatsApp -> acompanhamento', 50, '{"inbound_free_text": true}', 'follow_up', 'follow_up', true, true);
