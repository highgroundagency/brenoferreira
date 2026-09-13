-- 003 — pessoa (fato + operacional), PII separada, domicílio, filhos, necessidades, consentimento, tally, timeline
-- Existir em people = dado sensível (convicção religiosa, LGPD art. 5º, II). PII fica em people_contacts.

create table public.households (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  address_hash text not null,                     -- sha256(normalize(street|number|complement|postal_code)); só endereço fixo
  neighborhood_id uuid references public.neighborhoods(id),
  city_id uuid references public.cities(id),
  adults_count smallint,
  children_count smallint,
  merged_into_id uuid references public.households(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, address_hash)
);
create trigger households_set_updated_at before update on public.households for each row execute function public.set_updated_at();

create table public.people (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  client_uuid uuid not null unique,                -- idempotência da fila offline
  household_id uuid references public.households(id),
  neighborhood_id uuid not null references public.neighborhoods(id),
  city_id uuid not null references public.cities(id),
  age_range text check (age_range in ('18_24', '25_34', '35_49', '50_64', '65_plus')),   -- opcional (R-53)
  has_basic_need boolean not null default false,
  children_count smallint not null default 0 check (children_count between 0 and 15),
  needs_job boolean,
  occupation_area text,
  wants_training boolean,
  attends_church boolean,
  stage text not null default 'registered' check (stage in
    ('registered', 'first_contact_pending', 'journey_active', 'paused', 'inactive', 'opted_out', 'anonymized')),
  stage_changed_at timestamptz not null default now(),
  decided_at timestamptz not null default now(),
  source text not null default 'street' check (source in ('street', 'event', 'legacy_platform', 'referral', 'import')),
  registered_by uuid not null references public.profiles(id),
  duplicate_of_person_id uuid references public.people(id),
  review_status text not null default 'ok' check (review_status in ('ok', 'possible_duplicate', 'merged')),
  observation text,                                 -- ≤ 140 chars, só central/unit_admin
  consent_text_version text not null,
  first_contact_sent_at timestamptz,
  optin_confirmed_at timestamptz,
  last_contact_at timestamptz,
  anonymized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index people_unit_nbh_decided_idx on public.people (unit_id, neighborhood_id, decided_at);
create index people_unit_stage_idx on public.people (unit_id, stage);
create index people_household_idx on public.people (household_id);
create index people_registered_by_idx on public.people (registered_by, created_at desc);
create trigger people_set_updated_at before update on public.people for each row execute function public.set_updated_at();

create table public.people_contacts (
  person_id uuid primary key references public.people(id) on delete cascade,
  unit_id uuid not null references public.units(id),
  full_name text not null,
  phone_e164 text not null,
  wa_id text,                                       -- id canônico devolvido pela Meta no 1º envio (pode vir sem o 9º dígito)
  phone_owner text not null default 'self' check (phone_owner in ('self', 'family', 'other')),
  contact_name text,
  is_primary boolean not null default true,        -- false quando o mesmo número já é primário de outra pessoa
  email text,
  address_kind text not null default 'fixed' check (address_kind in ('fixed', 'no_number', 'occupation', 'no_fixed_address')),
  street text,
  number text,
  complement text,
  postal_code text,
  address_raw text,                                 -- ponto de referência / descrição livre
  whatsapp_valid boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index people_contacts_phone_primary_uidx on public.people_contacts (unit_id, phone_e164) where is_primary;
create index people_contacts_wa_id_idx on public.people_contacts (unit_id, wa_id);
create trigger people_contacts_set_updated_at before update on public.people_contacts for each row execute function public.set_updated_at();

create table public.children (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  age_band text not null check (age_band in ('0_5', '6_11', '12_14', '15_17', '18_plus')),
  created_at timestamptz not null default now()
);
create index children_person_idx on public.children (person_id);

create table public.needs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  household_id uuid references public.households(id),
  need_type text not null check (need_type in ('food', 'furniture', 'appliance', 'clothing', 'health', 'job', 'training', 'other')),
  item_code text,                                   -- cama, sofa, fogao, geladeira, maquina...
  raw_text text,
  detected_by text not null default 'evangelist' check (detected_by in ('evangelist', 'ai', 'team', 'person')),
  status text not null default 'open' check (status in ('open', 'routed', 'in_assistance', 'fulfilled', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index needs_person_idx on public.needs (person_id);
create index needs_unit_type_status_idx on public.needs (unit_id, need_type, status);
create trigger needs_set_updated_at before update on public.needs for each row execute function public.set_updated_at();

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  purpose text not null check (purpose in
    ('spiritual_followup', 'social_assistance', 'whatsapp_contact', 'marketing_events', 'share_with_church', 'share_with_employer', 'education_minor')),
  granted boolean not null,
  consent_text_version text not null,
  granted_at timestamptz not null default now(),
  given_via text not null default 'evangelist_app' check (given_via in ('evangelist_app', 'whatsapp_button', 'whatsapp_text', 'admin')),
  collected_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  confirmation_wamid text,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz not null default now(),
  unique (person_id, purpose, consent_text_version)
);
create index consents_person_purpose_idx on public.consents (person_id, purpose);

-- consents é quase append-only: só confirmação e revogação podem ser alteradas
create or replace function public.consents_guard_update() returns trigger
language plpgsql as $$
begin
  if new.person_id <> old.person_id or new.purpose <> old.purpose or new.granted <> old.granted
     or new.consent_text_version <> old.consent_text_version or new.granted_at <> old.granted_at
     or new.given_via <> old.given_via or new.collected_by is distinct from old.collected_by
     or new.unit_id <> old.unit_id then
    raise exception 'consents: only confirmed_at, confirmation_wamid, revoked_at and revoke_reason are updatable';
  end if;
  return new;
end $$;
create trigger consents_guard_update before update on public.consents for each row execute function public.consents_guard_update();

-- Contador anônimo: decisões por Jesus sem cadastro (recusa de dados ou menor sem responsável)
create table public.decision_tally (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  neighborhood_id uuid not null references public.neighborhoods(id),
  registered_by uuid not null references public.profiles(id),
  decided_on date not null default current_date,
  count integer not null default 0,
  minor_count integer not null default 0,
  unique (unit_id, neighborhood_id, registered_by, decided_on)
);

-- Timeline da pessoa (append-only)
create table public.person_events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid not null references public.people(id) on delete cascade,
  event_type text not null check (event_type in
    ('registered', 'referral_created', 'message_sent', 'optin_confirmed', 'video_watched', 'opted_out', 'stage_changed',
     'contact_attempt', 'data_request', 'anonymized', 'duplicate_marked', 'distinct_confirmed', 'need_added', 'note')),
  actor_profile_id uuid references public.profiles(id),
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index person_events_person_idx on public.person_events (person_id, occurred_at desc);

create or replace function public.reject_change() returns trigger
language plpgsql as $$
begin
  raise exception '% is append-only', tg_table_name;
end $$;
create trigger person_events_append_only before update or delete on public.person_events for each row execute function public.reject_change();

-- Mudança de estágio registrada na timeline
create or replace function public.people_stage_changed() returns trigger
language plpgsql as $$
begin
  if new.stage is distinct from old.stage then
    new.stage_changed_at := now();
    insert into public.person_events (unit_id, person_id, event_type, payload)
    values (new.unit_id, new.id, 'stage_changed', jsonb_build_object('from', old.stage, 'to', new.stage));
  end if;
  return new;
end $$;
create trigger people_stage_changed before update on public.people for each row execute function public.people_stage_changed();
