-- 009 — Fase 2b: educação (cursos, matrículas, instrutores), trabalho (empresas, contatos, vagas, colocações, importação),
-- igrejas e conexões, itens de casa (catálogo/estoque), pessoas da plataforma legada, impacto (mv_impact), retenção 24 meses.

create or replace function public.is_team_kind(p_kinds text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.team_members tm join public.teams t on t.id = tm.team_id join public.profiles p on p.id = tm.profile_id
                 where tm.profile_id = auth.uid() and tm.active and p.active and t.kind = any (p_kinds))
$$;
grant execute on function public.is_team_kind(text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Educação
-- ---------------------------------------------------------------------------
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  name text not null,
  audience text not null check (audience in ('teen', 'adult')),
  area text,
  partner text,
  seats integer,
  starts_at date,
  ends_at date,
  location text,
  instructor_profile_id uuid references public.profiles(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger courses_set_updated_at before update on public.courses for each row execute function public.set_updated_at();

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  course_id uuid not null references public.courses(id),
  person_id uuid not null references public.people(id) on delete cascade,
  child_id uuid references public.children(id) on delete set null,
  referral_id uuid references public.referrals(id),
  status text not null default 'enrolled' check (status in ('interested', 'enrolled', 'attending', 'completed', 'dropped')),
  certificate_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index enrollments_unique_idx on public.enrollments (course_id, person_id, coalesce(child_id, '00000000-0000-0000-0000-000000000000'::uuid));
create trigger enrollments_set_updated_at before update on public.enrollments for each row execute function public.set_updated_at();

create table public.volunteer_availability (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  time_slot text not null check (time_slot in ('morning', 'afternoon', 'evening')),
  skills text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (profile_id, weekday, time_slot)
);

-- ---------------------------------------------------------------------------
-- Trabalho: empresas, contatos, vagas, colocações, importação
-- ---------------------------------------------------------------------------
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  name text not null,
  legal_id text,                                        -- CNPJ só dígitos
  sector text,
  roles text[] not null default '{employer}',
  neighborhood_id uuid references public.neighborhoods(id),
  city_id uuid references public.cities(id),
  source text not null default 'manual' check (source in ('manual', 'legacy_import', 'partner')),
  legal_basis text not null default 'legitimate_interest_b2b',
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint companies_roles_chk check (roles <@ array['employer', 'benefit_partner']::text[])
);
create unique index companies_legal_id_uidx on public.companies (unit_id, legal_id) where legal_id is not null;
create index companies_name_trgm_idx on public.companies using gin (public.normalize_text(name) extensions.gin_trgm_ops);
create trigger companies_set_updated_at before update on public.companies for each row execute function public.set_updated_at();

create table public.company_contacts (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text,
  phone_e164 text,
  email text,
  role text,
  legal_basis text not null default 'legitimate_interest_b2b',
  created_at timestamptz not null default now()
);
create index company_contacts_phone_idx on public.company_contacts (unit_id, phone_e164);

create table public.job_openings (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null,
  area text,
  open_positions integer not null default 1,
  requirements text,
  status text not null default 'open' check (status in ('open', 'filled', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger job_openings_set_updated_at before update on public.job_openings for each row execute function public.set_updated_at();

create table public.job_placements (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  job_opening_id uuid not null references public.job_openings(id),
  referral_id uuid references public.referrals(id),
  status text not null default 'referred' check (status in ('referred', 'interviewed', 'hired', 'not_hired', 'dropped')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_id, job_opening_id)
);
create trigger job_placements_set_updated_at before update on public.job_placements for each row execute function public.set_updated_at();

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  kind text not null check (kind in ('companies', 'people_legacy')),
  file_name text,
  rows_total integer not null default 0,
  rows_imported integer not null default 0,
  rows_rejected integer not null default 0,
  log jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Igrejas
-- ---------------------------------------------------------------------------
create table public.churches (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  name text not null,
  neighborhood_id uuid references public.neighborhoods(id),
  address text,
  leader_name text,
  contact_phone_e164 text,
  service_times text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger churches_set_updated_at before update on public.churches for each row execute function public.set_updated_at();

create table public.church_connections (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  church_id uuid not null references public.churches(id),
  status text not null default 'suggested' check (status in ('suggested', 'invited', 'visited', 'connected', 'declined')),
  connected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_id, church_id)
);
create trigger church_connections_set_updated_at before update on public.church_connections for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Itens de casa: catálogo e estoque
-- ---------------------------------------------------------------------------
create table public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),
  code text not null,
  name text not null,
  category text not null check (category in ('furniture', 'appliance', 'other')),
  active boolean not null default true,
  unique (unit_id, code)
);
insert into public.catalog_items (unit_id, code, name, category) values
  (null, 'cama', 'Cama', 'furniture'), (null, 'sofa', 'Sofá', 'furniture'), (null, 'mesa', 'Mesa', 'furniture'),
  (null, 'fogao', 'Fogão', 'appliance'), (null, 'geladeira', 'Geladeira', 'appliance'), (null, 'maquina', 'Máquina de lavar', 'appliance')
on conflict do nothing;

create table public.inventory_stock (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  item_code text not null,
  quantity integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (unit_id, item_code)
);
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  item_code text not null,
  delta integer not null,
  reason text not null check (reason in ('donation', 'delivery', 'adjustment', 'return')),
  ref_id uuid,
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create or replace function public.inventory_apply() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.inventory_stock (unit_id, item_code, quantity) values (new.unit_id, new.item_code, new.delta)
  on conflict (unit_id, item_code) do update set quantity = public.inventory_stock.quantity + excluded.quantity, updated_at = now();
  return new;
end $$;
create trigger inventory_movements_apply after insert on public.inventory_movements for each row execute function public.inventory_apply();

-- ---------------------------------------------------------------------------
-- Segmento padrão: empresário/autônomo declarado no cadastro
-- ---------------------------------------------------------------------------
create or replace function public.people_segment_default() returns trigger
language plpgsql as $$
begin
  if new.profile_segment is null and new.occupation_area = 'autônomo/empresário' then new.profile_segment := 'business'; end if;
  return new;
end $$;
create trigger people_segment_default before insert on public.people for each row execute function public.people_segment_default();

-- ---------------------------------------------------------------------------
-- Templates da fase
-- ---------------------------------------------------------------------------
insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables) values
  (null, 'transtornar_igreja_convite_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   'Olá {{1}}! Uma igreja perto de você para caminhar junto: {{2}} — {{3}}. Para parar, responda SAIR.', '[]', '["first_name","church_name","details"]'),
  (null, 'transtornar_curso_v1', 'pt_BR', 'UTILITY', 'pending', 'none',
   'Olá {{1}}, aqui é o Transtornar: {{2}}', '[]', '["first_name","details"]')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Funções: educação
-- ---------------------------------------------------------------------------
create or replace function public.assert_staff_or_team(p_unit_id uuid, p_kinds text[]) returns void
language plpgsql stable as $$
begin
  if not (public.can_write_unit(p_unit_id) or (public.auth_unit_id() = p_unit_id and public.is_team_kind(p_kinds))) then raise insufficient_privilege; end if;
end $$;

create or replace function public.enroll_person(p_person_id uuid, p_course_id uuid, p_child_id uuid default null, p_referral_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_id uuid; c record; v_phone text; v_first text;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  perform public.assert_staff_or_team(v_unit, array['education', 'central']);
  select * into c from public.courses where id = p_course_id and unit_id = v_unit and active;
  if c.id is null then raise exception 'course_not_found'; end if;
  if c.seats is not null and (select count(*) from public.enrollments e where e.course_id = c.id and e.status in ('enrolled', 'attending')) >= c.seats then raise exception 'course_full'; end if;
  insert into public.enrollments (unit_id, course_id, person_id, child_id, referral_id, status) values (v_unit, p_course_id, p_person_id, p_child_id, p_referral_id, 'enrolled')
  on conflict (course_id, person_id, coalesce(child_id, '00000000-0000-0000-0000-000000000000'::uuid)) do update set status = 'enrolled' returning id into v_id;
  if p_referral_id is not null then
    update public.referrals set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), assigned_to = coalesce(assigned_to, auth.uid()) where id = p_referral_id and status in ('new', 'triaged');
  end if;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, p_person_id, 'enrolled', auth.uid(), jsonb_build_object('course', c.name, 'child_id', p_child_id));
  select pc.phone_e164, split_part(pc.full_name, ' ', 1) into v_phone, v_first from public.people_contacts pc where pc.person_id = p_person_id;
  if v_phone is not null and exists (select 1 from public.consents co where co.person_id = p_person_id and co.purpose = 'whatsapp_contact' and co.granted and co.revoked_at is null) then
    insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, status, scheduled_for, payload, pricing_category)
    values (v_unit, p_person_id, v_phone, 'template', 'transtornar_curso_v1', 'queued', public.next_send_slot(v_unit, now()),
            jsonb_build_object('first_name', v_first, 'body_params', jsonb_build_array(v_first, 'matrícula confirmada no curso ' || c.name || coalesce(' a partir de ' || to_char(c.starts_at, 'DD/MM'), '') || coalesce(' em ' || c.location, '') || '.')), 'utility');
  end if;
  return v_id;
end $$;

create or replace function public.enrollment_transition(p_enrollment_id uuid, p_to text, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e record;
begin
  select * into e from public.enrollments where id = p_enrollment_id;
  if e.id is null then raise exception 'enrollment_not_found'; end if;
  perform public.assert_staff_or_team(e.unit_id, array['education', 'central']);
  if not ((e.status = 'interested' and p_to in ('enrolled', 'dropped')) or (e.status = 'enrolled' and p_to in ('attending', 'completed', 'dropped'))
       or (e.status = 'attending' and p_to in ('completed', 'dropped'))) then
    raise exception 'invalid_transition % -> %', e.status, p_to;
  end if;
  update public.enrollments set status = p_to, certificate_note = coalesce(p_note, certificate_note) where id = e.id;
  if p_to in ('completed', 'dropped') and e.referral_id is not null then
    update public.referrals set status = case when p_to = 'completed' then 'done' else 'cancelled' end, done_at = case when p_to = 'completed' then now() end,
      outcome = case when p_to = 'completed' then 'curso concluído' end, cancelled_reason = case when p_to = 'dropped' then 'desistiu do curso' end
    where id = e.referral_id and status not in ('done', 'cancelled');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Funções: trabalho
-- ---------------------------------------------------------------------------
create or replace function public.import_companies(p_rows jsonb, p_file_name text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id(); r jsonb; v_cnpj text; v_phone text; v_company uuid; v_batch uuid; v_imp integer := 0; v_rej integer := 0; v_log jsonb := '[]'::jsonb; v_nbh uuid; v_city uuid; i integer := 0;
begin
  perform public.assert_role('central', 'unit_admin');
  insert into public.import_batches (unit_id, kind, file_name, rows_total, created_by) values (v_unit, 'companies', p_file_name, jsonb_array_length(p_rows), auth.uid()) returning id into v_batch;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      if coalesce(r->>'name', '') = '' then raise exception 'sem nome'; end if;
      v_cnpj := nullif(regexp_replace(coalesce(r->>'cnpj', ''), '\D', '', 'g'), '');
      if v_cnpj is not null and length(v_cnpj) <> 14 then raise exception 'CNPJ inválido'; end if;
      v_phone := case when coalesce(r->>'contact_phone', '') <> '' then public.normalize_e164(r->>'contact_phone') end;
      v_nbh := null; v_city := null;
      if coalesce(r->>'neighborhood', '') <> '' then
        select n.id, n.city_id into v_nbh, v_city from public.neighborhoods n join public.unit_neighborhoods un on un.neighborhood_id = n.id and un.unit_id = v_unit
        where n.normalized_name = public.normalize_text(r->>'neighborhood') or public.normalize_text(r->>'neighborhood') = any (n.aliases) limit 1;
      end if;
      v_company := null;
      if v_cnpj is not null then select id into v_company from public.companies where unit_id = v_unit and legal_id = v_cnpj; end if;
      if v_company is null and v_phone is not null then
        select cc.company_id into v_company from public.company_contacts cc where cc.unit_id = v_unit and cc.phone_e164 = v_phone limit 1;
      end if;
      if v_company is null then
        select id into v_company from public.companies where unit_id = v_unit and legal_id is null and public.normalize_text(name) = public.normalize_text(r->>'name') limit 1;
      end if;
      if v_company is null then
        insert into public.companies (unit_id, name, legal_id, sector, roles, neighborhood_id, city_id, source, notes)
        values (v_unit, r->>'name', v_cnpj, nullif(r->>'sector', ''), case when coalesce(r->>'role', 'employer') = 'benefit_partner' then '{benefit_partner}'::text[] when coalesce(r->>'role', '') = 'both' then '{employer,benefit_partner}'::text[] else '{employer}'::text[] end,
                v_nbh, v_city, 'legacy_import', nullif(r->>'notes', ''))
        returning id into v_company;
      else
        update public.companies set sector = coalesce(nullif(r->>'sector', ''), sector), legal_id = coalesce(legal_id, v_cnpj), neighborhood_id = coalesce(neighborhood_id, v_nbh), updated_at = now() where id = v_company;
      end if;
      if v_phone is not null or coalesce(r->>'contact_email', '') <> '' then
        if not exists (select 1 from public.company_contacts cc where cc.company_id = v_company and (cc.phone_e164 = v_phone or (cc.email is not null and lower(cc.email) = lower(r->>'contact_email')))) then
          insert into public.company_contacts (unit_id, company_id, name, phone_e164, email, role) values (v_unit, v_company, nullif(r->>'contact_name', ''), v_phone, nullif(lower(r->>'contact_email'), ''), nullif(r->>'contact_role', ''));
        end if;
      end if;
      if coalesce(r->>'job_role', '') <> '' then
        insert into public.job_openings (unit_id, company_id, role, area, open_positions)
        select v_unit, v_company, r->>'job_role', nullif(r->>'area', ''), greatest(1, coalesce((r->>'open_positions')::int, 1))
        where not exists (select 1 from public.job_openings jo where jo.company_id = v_company and jo.role = r->>'job_role' and jo.status = 'open');
      end if;
      v_imp := v_imp + 1;
    exception when others then
      v_rej := v_rej + 1;
      v_log := v_log || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;
  update public.import_batches set rows_imported = v_imp, rows_rejected = v_rej, log = v_log where id = v_batch;
  return jsonb_build_object('batch_id', v_batch, 'imported', v_imp, 'rejected', v_rej, 'log', v_log);
end $$;

create or replace function public.refer_to_job(p_person_id uuid, p_job_opening_id uuid, p_referral_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_id uuid; jo record;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  perform public.assert_staff_or_team(v_unit, array['employment', 'central']);
  select jo2.*, c.name as company_name into jo from public.job_openings jo2 join public.companies c on c.id = jo2.company_id where jo2.id = p_job_opening_id and jo2.unit_id = v_unit and jo2.status = 'open';
  if jo.id is null then raise exception 'job_opening_not_open'; end if;
  if not exists (select 1 from public.consents co where co.person_id = p_person_id and co.purpose = 'share_with_employer' and co.granted and co.revoked_at is null) then
    raise exception 'consent_share_with_employer_required';
  end if;
  insert into public.job_placements (unit_id, person_id, job_opening_id, referral_id) values (v_unit, p_person_id, p_job_opening_id, p_referral_id)
  on conflict (person_id, job_opening_id) do update set status = 'referred' returning id into v_id;
  if p_referral_id is not null then
    update public.referrals set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), assigned_to = coalesce(assigned_to, auth.uid()) where id = p_referral_id and status in ('new', 'triaged');
  end if;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, p_person_id, 'job_placement', auth.uid(), jsonb_build_object('company', jo.company_name, 'role', jo.role, 'status', 'referred'));
  return v_id;
end $$;

create or replace function public.placement_transition(p_placement_id uuid, p_to text, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare pl record;
begin
  select * into pl from public.job_placements where id = p_placement_id;
  if pl.id is null then raise exception 'placement_not_found'; end if;
  perform public.assert_staff_or_team(pl.unit_id, array['employment', 'central']);
  if not ((pl.status = 'referred' and p_to in ('interviewed', 'hired', 'not_hired', 'dropped')) or (pl.status = 'interviewed' and p_to in ('hired', 'not_hired', 'dropped'))) then
    raise exception 'invalid_transition % -> %', pl.status, p_to;
  end if;
  update public.job_placements set status = p_to, note = coalesce(p_note, note) where id = pl.id;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (pl.unit_id, pl.person_id, 'job_placement', auth.uid(), jsonb_build_object('status', p_to));
  if p_to = 'hired' then
    update public.job_openings set open_positions = greatest(0, open_positions - 1), status = case when open_positions - 1 <= 0 then 'filled' else status end where id = pl.job_opening_id;
    if pl.referral_id is not null then update public.referrals set status = 'done', done_at = now(), outcome = 'contratado' where id = pl.referral_id and status not in ('done', 'cancelled'); end if;
  end if;
end $$;

-- consentimento de compartilhar com empregador (colhido pela central/acompanhamento por telefone ou WhatsApp)
create or replace function public.grant_consent(p_person_id uuid, p_purpose text, p_via text default 'admin') returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_version text;
begin
  select unit_id, consent_text_version into v_unit, v_version from public.people where id = p_person_id;
  perform public.assert_staff_or_team(v_unit, array['follow_up', 'employment', 'education', 'central']);
  if p_purpose not in ('share_with_employer', 'share_with_church', 'marketing_events', 'education_minor', 'benefits_club') then raise exception 'purpose_not_allowed'; end if;
  insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via, collected_by)
  values (v_unit, p_person_id, p_purpose, true, v_version, p_via, auth.uid())
  on conflict (person_id, purpose, consent_text_version) do update set revoked_at = null, revoke_reason = null;
end $$;

-- ---------------------------------------------------------------------------
-- Funções: igrejas
-- ---------------------------------------------------------------------------
create or replace function public.suggest_church(p_person_id uuid) returns setof public.churches
language sql stable security definer set search_path = public as $$
  select c.* from public.churches c join public.people p on p.unit_id = c.unit_id
  where p.id = p_person_id and c.active
  order by (c.neighborhood_id = p.neighborhood_id) desc, c.name limit 5
$$;

create or replace function public.connect_church(p_person_id uuid, p_church_id uuid, p_status text default 'invited') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid; v_id uuid; c record; v_phone text; v_first text;
begin
  select unit_id into v_unit from public.people where id = p_person_id;
  perform public.assert_staff_or_team(v_unit, array['follow_up', 'central']);
  select * into c from public.churches where id = p_church_id and unit_id = v_unit;
  if c.id is null then raise exception 'church_not_found'; end if;
  if p_status in ('invited', 'connected') and not exists (select 1 from public.consents co where co.person_id = p_person_id and co.purpose = 'share_with_church' and co.granted and co.revoked_at is null) then
    raise exception 'consent_share_with_church_required';
  end if;
  insert into public.church_connections (unit_id, person_id, church_id, status, connected_at) values (v_unit, p_person_id, p_church_id, p_status, case when p_status = 'connected' then now() end)
  on conflict (person_id, church_id) do update set status = excluded.status, connected_at = coalesce(public.church_connections.connected_at, excluded.connected_at) returning id into v_id;
  if p_status = 'invited' then
    select pc.phone_e164, split_part(pc.full_name, ' ', 1) into v_phone, v_first from public.people_contacts pc where pc.person_id = p_person_id;
    if v_phone is not null and exists (select 1 from public.consents co where co.person_id = p_person_id and co.purpose = 'whatsapp_contact' and co.granted and co.revoked_at is null) then
      insert into public.message_log (unit_id, person_id, to_phone_e164, kind, template_name, status, scheduled_for, payload)
      values (v_unit, p_person_id, v_phone, 'template', 'transtornar_igreja_convite_v1', 'queued', public.next_send_slot(v_unit, now()),
              jsonb_build_object('first_name', v_first, 'body_params', jsonb_build_array(v_first, c.name, concat_ws(' · ', c.address, c.service_times, c.leader_name))));
    end if;
  end if;
  if p_status = 'connected' then
    update public.people set stage = 'church_connected', attends_church = true where id = p_person_id and stage in ('journey_active', 'day7_done', 'day16_done', 'inactive', 'paused');
    perform public.add_points(p_person_id, 'church_connected', v_id);
    update public.referrals set status = 'done', done_at = now(), outcome = 'conectado a ' || c.name where person_id = p_person_id and referral_type = 'church_connection' and status not in ('done', 'cancelled');
  end if;
  insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, p_person_id, 'church_interest', auth.uid(), jsonb_build_object('church', c.name, 'status', p_status));
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Funções: itens de casa
-- ---------------------------------------------------------------------------
create or replace function public.fulfill_home_item(p_referral_id uuid, p_item_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare r record; v_qty integer; v_id uuid; v_snapshot jsonb;
begin
  select * into r from public.referrals where id = p_referral_id and referral_type = 'home_items';
  if r.id is null then raise exception 'referral_not_found'; end if;
  perform public.assert_staff_or_team(r.unit_id, array['home_items', 'logistics', 'central']);
  select quantity into v_qty from public.inventory_stock where unit_id = r.unit_id and item_code = p_item_code;
  if coalesce(v_qty, 0) < 1 then raise exception 'out_of_stock'; end if;
  select jsonb_build_object('street', pc.street, 'number', pc.number, 'complement', pc.complement, 'postal_code', pc.postal_code, 'reference', pc.address_raw, 'kind', pc.address_kind, 'phone', pc.phone_e164)
    into v_snapshot from public.people_contacts pc where pc.person_id = r.person_id;
  insert into public.inventory_movements (unit_id, item_code, delta, reason, ref_id, created_by) values (r.unit_id, p_item_code, -1, 'delivery', r.id, auth.uid());
  insert into public.delivery_orders (unit_id, referral_id, person_id, household_id, kind, item_code, scheduled_for, address_snapshot)
  values (r.unit_id, r.id, r.person_id, r.household_id, 'home_item', p_item_code, current_date + 1, v_snapshot) returning id into v_id;
  update public.referrals set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), assigned_to = coalesce(assigned_to, auth.uid()) where id = r.id and status in ('new', 'triaged');
  return v_id;
end $$;

create or replace function public.add_stock(p_item_code text, p_delta integer, p_reason text default 'donation', p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id();
begin
  perform public.assert_staff_or_team(v_unit, array['home_items', 'logistics', 'central']);
  insert into public.inventory_movements (unit_id, item_code, delta, reason, note, created_by) values (v_unit, p_item_code, p_delta, p_reason, p_note, auth.uid());
end $$;

-- ---------------------------------------------------------------------------
-- Pessoas da plataforma legada: entram sem consentimento de WhatsApp => só contato humano
-- ---------------------------------------------------------------------------
create or replace function public.import_legacy_people(p_rows jsonb, p_file_name text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_unit uuid := public.auth_unit_id(); r jsonb; v_phone text; v_nbh uuid; v_city uuid; v_person uuid; v_batch uuid; v_imp integer := 0; v_rej integer := 0; v_log jsonb := '[]'::jsonb; i integer := 0; v_team uuid;
begin
  perform public.assert_role('central', 'unit_admin');
  insert into public.import_batches (unit_id, kind, file_name, rows_total, created_by) values (v_unit, 'people_legacy', p_file_name, jsonb_array_length(p_rows), auth.uid()) returning id into v_batch;
  select t.id into v_team from public.teams t where t.unit_id = v_unit and t.kind = 'follow_up' and t.active and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
  if v_team is null then select t.id into v_team from public.teams t where t.unit_id = v_unit and t.kind = 'central'; end if;
  perform set_config('app.skip_routing', 'on', true);
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      v_phone := public.normalize_e164(coalesce(r->>'phone', ''));
      if v_phone !~ '^\+\d{10,15}$' then raise exception 'telefone inválido'; end if;
      if exists (select 1 from public.people_contacts pc where pc.unit_id = v_unit and pc.phone_e164 = any (public.phone_variants(v_phone))) then raise exception 'telefone já cadastrado'; end if;
      select n.id, n.city_id into v_nbh, v_city from public.neighborhoods n join public.unit_neighborhoods un on un.neighborhood_id = n.id and un.unit_id = v_unit
      where n.normalized_name = public.normalize_text(coalesce(r->>'neighborhood', '')) or public.normalize_text(coalesce(r->>'neighborhood', '')) = any (n.aliases) limit 1;
      if v_nbh is null then raise exception 'bairro não encontrado'; end if;
      insert into public.people (unit_id, client_uuid, neighborhood_id, city_id, decided_at, source, registered_by, consent_text_version, stage)
      values (v_unit, gen_random_uuid(), v_nbh, v_city, coalesce((r->>'decided_at')::timestamptz, now()), 'legacy_platform', auth.uid(), 'none', 'registered') returning id into v_person;
      insert into public.people_contacts (person_id, unit_id, full_name, phone_e164, address_kind, address_raw) values (v_person, v_unit, coalesce(nullif(r->>'full_name', ''), 'Sem nome'), v_phone, 'no_fixed_address', nullif(r->>'address', ''));
      insert into public.referrals (unit_id, person_id, team_id, referral_type, reason, priority) values (v_unit, v_person, v_team, 'follow_up', 'recontato humano (plataforma legada) — colher consentimento antes de qualquer mensagem', 2);
      insert into public.person_events (unit_id, person_id, event_type, actor_profile_id, payload) values (v_unit, v_person, 'imported', auth.uid(), jsonb_build_object('batch', v_batch, 'source', 'legacy_platform'));
      v_imp := v_imp + 1;
    exception when others then
      v_rej := v_rej + 1; v_log := v_log || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;
  update public.import_batches set rows_imported = v_imp, rows_rejected = v_rej, log = v_log where id = v_batch;
  return jsonb_build_object('batch_id', v_batch, 'imported', v_imp, 'rejected', v_rej, 'log', v_log);
end $$;

-- Consentimento colhido pela central para pessoa importada: libera o primeiro contato
create or replace function public.activate_legacy_person(p_person_id uuid, p_consent_version text default 'v1') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_unit uuid;
begin
  select unit_id into v_unit from public.people where id = p_person_id and source = 'legacy_platform';
  if v_unit is null then raise exception 'not_legacy_person'; end if;
  perform public.assert_staff_or_team(v_unit, array['follow_up', 'central']);
  update public.people set consent_text_version = p_consent_version where id = p_person_id;
  insert into public.consents (unit_id, person_id, purpose, granted, consent_text_version, given_via, collected_by)
  values (v_unit, p_person_id, 'spiritual_followup', true, p_consent_version, 'admin', auth.uid()), (v_unit, p_person_id, 'whatsapp_contact', true, p_consent_version, 'admin', auth.uid())
  on conflict do nothing;
  perform public.apply_routing_rules(p_person_id);
  return public.enqueue_first_contact(p_person_id);
end $$;

-- ---------------------------------------------------------------------------
-- Retenção v3: 24 meses sem interação e sem nada ativo => anonimização
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
    select t.id into v_team from public.teams t where t.unit_id = r.unit_id and t.kind = 'follow_up' and t.active and exists (select 1 from public.team_members tm where tm.team_id = t.id and tm.active);
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
  for r in select pe.id from public.people pe
           where pe.stage <> 'anonymized'
             and greatest(pe.created_at, pe.stage_changed_at, coalesce(pe.last_contact_at, pe.created_at)) < now() - interval '24 months'
             and not exists (select 1 from public.assistance_programs ap where ap.person_id = pe.id and ap.status = 'active')
             and not exists (select 1 from public.referrals x where x.person_id = pe.id and x.status not in ('done', 'cancelled'))
             and not exists (select 1 from public.enrollments e where e.person_id = pe.id and e.status in ('enrolled', 'attending'))
             and not exists (select 1 from public.job_placements jp where jp.person_id = pe.id and jp.status in ('referred', 'interviewed')) loop
    perform public.anonymize_person(r.id, 'retention_24m'); v_anon := v_anon + 1;
  end loop;
  delete from public.wa_inbound_events where created_at < now() - interval '90 days';
  return jsonb_build_object('inactivated', v_inactive, 'anonymized', v_anon);
end $$;

-- ---------------------------------------------------------------------------
-- Impacto (relatórios institucionais; k >= 5 nas visões públicas)
-- ---------------------------------------------------------------------------
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
    now() as refreshed_at
  from public.units u;
create unique index mv_impact_unit_idx on public.mv_impact (unit_id);
create or replace function public.refresh_impact() returns void
language plpgsql security definer set search_path = public as $$
begin
  refresh materialized view concurrently public.mv_impact;
end $$;
create or replace view public.v_impact_by_unit with (security_invoker = true) as
  select m.* from public.mv_impact m where public.can_read_unit(m.unit_id);
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('impact-refresh', '0 3 * * *', $c$ select public.refresh_impact() $c$);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Grants e RLS
-- ---------------------------------------------------------------------------
grant execute on function public.enroll_person(uuid, uuid, uuid, uuid), public.enrollment_transition(uuid, text, text), public.import_companies(jsonb, text),
  public.refer_to_job(uuid, uuid, uuid), public.placement_transition(uuid, text, text), public.grant_consent(uuid, text, text), public.suggest_church(uuid),
  public.connect_church(uuid, uuid, text), public.fulfill_home_item(uuid, text), public.add_stock(text, integer, text, text), public.import_legacy_people(jsonb, text),
  public.activate_legacy_person(uuid, text), public.refresh_impact() to authenticated;
grant execute on all functions in schema public to service_role;
grant select on public.mv_impact to authenticated;

alter table public.courses enable row level security;
alter table public.enrollments enable row level security;
alter table public.volunteer_availability enable row level security;
alter table public.companies enable row level security;
alter table public.company_contacts enable row level security;
alter table public.job_openings enable row level security;
alter table public.job_placements enable row level security;
alter table public.import_batches enable row level security;
alter table public.churches enable row level security;
alter table public.church_connections enable row level security;
alter table public.catalog_items enable row level security;
alter table public.inventory_stock enable row level security;
alter table public.inventory_movements enable row level security;

create policy courses_select on public.courses for select to authenticated using (public.can_read_unit(unit_id));
create policy courses_write on public.courses for all to authenticated using (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['education']))) with check (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['education'])));
create policy enrollments_select on public.enrollments for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['education'])));
create policy volunteer_availability_rw on public.volunteer_availability for all to authenticated using (profile_id = auth.uid() or public.can_write_unit(unit_id)) with check (profile_id = auth.uid() or public.can_write_unit(unit_id));
create policy companies_select on public.companies for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy companies_write on public.companies for all to authenticated using (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment']))) with check (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy company_contacts_select on public.company_contacts for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy company_contacts_write on public.company_contacts for all to authenticated using (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment']))) with check (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy job_openings_select on public.job_openings for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy job_openings_write on public.job_openings for all to authenticated using (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment']))) with check (public.can_write_unit(unit_id) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy job_placements_select on public.job_placements for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['employment'])));
create policy import_batches_select on public.import_batches for select to authenticated using (public.is_unit_staff() and public.can_read_unit(unit_id));
create policy churches_select on public.churches for select to authenticated using (public.can_read_unit(unit_id));
create policy churches_write on public.churches for all to authenticated using (public.can_write_unit(unit_id)) with check (public.can_write_unit(unit_id));
create policy church_connections_select on public.church_connections for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['follow_up'])));
create policy catalog_items_select on public.catalog_items for select to authenticated using (unit_id is null or unit_id = public.auth_unit_id() or public.auth_role() = 'global_admin');
create policy catalog_items_write on public.catalog_items for all to authenticated
  using ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'))
  with check ((unit_id is null and public.auth_role() = 'global_admin') or (unit_id = public.auth_unit_id() and public.auth_role() = 'unit_admin'));
create policy inventory_stock_select on public.inventory_stock for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['home_items', 'logistics'])));
create policy inventory_movements_select on public.inventory_movements for select to authenticated using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or (unit_id = public.auth_unit_id() and public.is_team_kind(array['home_items', 'logistics'])));
