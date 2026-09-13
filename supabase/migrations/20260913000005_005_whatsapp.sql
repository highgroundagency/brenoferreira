-- 005 — WhatsApp (recorte da Fase 1): templates espelhados da Meta, conteúdo, log de mensagens e eventos inbound

create table public.message_templates (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),        -- null = global
  name text not null,                               -- ex.: transtornar_video1_v1
  language text not null default 'pt_BR',
  category text not null default 'MARKETING' check (category in ('UTILITY', 'MARKETING', 'AUTHENTICATION')),
  meta_template_id text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paused', 'disabled')),
  header_type text check (header_type in ('none', 'text', 'video', 'image', 'document')),
  body_text text,
  buttons jsonb not null default '[]'::jsonb,       -- [{"id":"optin_yes","title":"Quero receber"}, ...]
  variables jsonb not null default '[]'::jsonb,     -- ["first_name"]
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, name, language)
);
create trigger message_templates_set_updated_at before update on public.message_templates for each row execute function public.set_updated_at();

create table public.content_assets (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),        -- null = global
  key text not null,                                -- ex.: video_1
  title text not null,
  media_type text not null check (media_type in ('video', 'image', 'document', 'link')),
  public_url text not null,                         -- bucket público "content" (≤ 16 MB para vídeo)
  duration_seconds integer,
  source text not null default 'new' check (source in ('new', 'legacy_platform')),
  rights_ok boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, key)
);
create trigger content_assets_set_updated_at before update on public.content_assets for each row execute function public.set_updated_at();

create table public.message_log (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id),
  person_id uuid references public.people(id) on delete set null,
  profile_id uuid references public.profiles(id),
  to_phone_e164 text,
  kind text not null check (kind in ('template', 'interactive', 'text', 'media')),
  template_name text,
  content_asset_id uuid references public.content_assets(id),
  provider text not null default 'meta_cloud',
  provider_message_id text unique,
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'delivered', 'read', 'failed', 'skipped')),
  skip_reason text,
  error_code text,
  error_message text,
  payload jsonb not null default '{}'::jsonb,       -- variáveis/texto; nunca conteúdo sensível além do necessário
  attempts smallint not null default 0,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index message_log_queued_idx on public.message_log (scheduled_for) where status = 'queued';
create index message_log_person_idx on public.message_log (person_id, created_at desc);
create trigger message_log_set_updated_at before update on public.message_log for each row execute function public.set_updated_at();

create table public.wa_inbound_events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references public.units(id),
  dedup_key text unique not null,                   -- sha256(wamid||event_type||status||timestamp)
  wamid text,
  phone_number_id text,
  wa_id text,
  event_type text not null check (event_type in ('message', 'status', 'error', 'quality_update', 'template_update', 'unknown')),
  raw jsonb not null,
  processed_at timestamptz,
  error text,
  created_at timestamptz not null default now()
);
create index wa_inbound_events_unprocessed_idx on public.wa_inbound_events (created_at) where processed_at is null;

-- Templates globais da Fase 1 (status/categoria são espelhados da Graph API após a submissão — Fase 0 c)
insert into public.message_templates (unit_id, name, language, category, status, header_type, body_text, buttons, variables) values
  (null, 'transtornar_video1_v1', 'pt_BR', 'MARKETING', 'pending', 'video',
   'Olá {{1}}! Aqui é o Transtornar. Preparamos este vídeo para você. Para parar a qualquer momento, responda SAIR.',
   '[{"id":"video_watched","title":"Quero continuar"},{"id":"stop","title":"Parar"}]', '["first_name"]'),
  (null, 'transtornar_optin_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   'Olá {{1}}! Aqui é o Transtornar. Registramos seu contato hoje. Quer receber nossas mensagens e vídeos? Para parar, responda SAIR.',
   '[{"id":"optin_yes","title":"Quero receber"},{"id":"optin_no","title":"Agora não"}]', '["first_name"]'),
  (null, 'transtornar_lembrete_v1', 'pt_BR', 'MARKETING', 'pending', 'none',
   'Olá {{1}}, aqui é o Transtornar de novo. Quer receber nossas mensagens? Para parar, responda SAIR.',
   '[{"id":"optin_yes","title":"Quero receber"},{"id":"optin_no","title":"Agora não"}]', '["first_name"]')
on conflict do nothing;
