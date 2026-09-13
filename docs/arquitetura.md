# Transtornar — Documento de Arquitetura Final

Versão 1.0 · 2026-09-12 · Base: proposta vencedora (P0) + enxertos de P1/P2/P3 + correções aos pontos em que todas erraram. Público: Claude Code (implementador) e a agência High Ground. Cliente: Breno Ferreira / Transtornar. Cidade-piloto: Curitiba/PR.

---

## 0. Decisões fechadas em uma página

| Tema | Decisão |
|---|---|
| App do evangelista | PWA Next.js 15 (App Router, TypeScript), instalável, offline-first. Sem Expo no MVP. |
| Painel da central | Mesmo app Next.js, rotas `/central` e `/admin`, papéis por JWT + RLS. |
| Backend | Supabase novo (`transtornar-prod`, sa-east-1, Postgres 17, plano Pro): Auth, RLS, Storage, Edge Functions, `pg_cron` + `pg_net`, Realtime. Um único app na raiz do repositório, sem monorepo. |
| Automação | Padrão outbox no Postgres (`outbox_events`) + Database Webhook + `pg_cron` de retry. Sem n8n/Make/pgmq. |
| WhatsApp | WhatsApp Business Platform — Cloud API oficial da Meta, integração direta (sem BSP), atrás da interface `WhatsAppProvider`. Z-API/Evolution proibidos. **Titular do Business Manager/WABA/número = Transtornar (controlador); a agência é parceira/operadora.** |
| Primeiro contato | Opt-in duplo: consentimento no app + template **neutro** (não revela convicção religiosa) com botões "Quero receber" / "Agora não". O vídeo 1 só vai depois do clique, dentro da janela de 24 h (mídia gratuita). |
| IA | API da Anthropic, só server-side. `claude-haiku-4-5` (classificação de texto livre + resumo de caso, desde o MVP), `claude-sonnet-5` (assistente conversacional, Fase 2), `claude-opus-5` (digest semanal/matching, Fase 2+ em batch). `claude-fable-5-1` não entra no produto. IDs exatos, sem sufixo de data. |
| Login do evangelista | Convite por link com código → define senha; login e-mail + senha; sessão de 30 dias. Magic link **não** é o fluxo principal (em PWA iOS abre no Safari, fora do app instalado). OTP por WhatsApp: Fase 2. |
| Bairro | Select normalizado (75 bairros oficiais de Curitiba, tabela de referência **global**), com aliases + `unaccent`/`pg_trgm`. CEP via ViaCEP (grátis). **Google Geocoding fica para a Fase 2** (lat/lng só a logística consome). |
| Multi-tenant | `units` = tenant; `unit_id NOT NULL` em toda tabela operacional desde a migration 001; claims `unit_id`/`role`/`team_ids` no JWT via Custom Access Token Hook; teste de isolamento com 2ª unidade no CI. Tabelas de referência (`cities`, `neighborhoods`) globais, ligadas à unidade por `unit_neighborhoods`. |
| Deduplicação | Suave: telefone repetido não bloqueia; cria `review_status='possible_duplicate'` + `duplicate_of_person_id`; a jornada nunca inicia duas vezes para o mesmo `phone_hash` na unidade. Idempotência offline por `client_uuid`. |
| LGPD | Toda a base `people` é dado sensível (art. 5º, II). Base legal: consentimento específico e destacado (art. 11, I) — sem legítimo interesse sobre `people`. PII em tabela separada (`people_contacts`) com RLS própria. Menor de 18 cadastrado só com responsável. Sem GPS do evangelista. Contador anônimo de decisões sem consentimento (`decision_tally`). RIPD na Fase 1. |
| Estratégia | Não recebe `referral` por pessoa: recebe dashboard + digest semanal. |
| Operação humana no MVP | "Modo central única": uma pessoa vê todas as filas em uma tela; times sem membros ativos caem na central; horário de operação declarado; mensagens ao convertido nunca prometem prazo. |
| Fase 1 | Marco 1a (semanas 1-2): cadastro + aviso à central + template de opt-in + vídeo 1, de pé em campo. Marco 1b (semanas 3-5): painel mínimo, filas, métricas por bairro, hardening, piloto. Go-live na semana 6. |

---

## 1. Stack

| Camada | Escolha | Justificativa |
|---|---|---|
| App de campo | Next.js 15 + React 19 + TypeScript, Tailwind + shadcn/ui, `react-hook-form` + `zod`, Serwist (service worker), Dexie (IndexedDB, fila offline), `libphonenumber-js` (E.164) | Um codebase para app e painel; instala por link/QR sem loja; atualização instantânea; corpus Next.js/Supabase que o Claude Code domina. Expo só se push nativo/câmera intensiva virarem críticos (Capacitor como saída sem reescrita). |
| Painel | Mesmo projeto, route groups `(campo)`, `(central)`, `(admin)`; TanStack Table; Supabase Realtime | Zero infra extra; RLS única. |
| Banco/BaaS | Supabase Pro, sa-east-1, Postgres 17; extensões `pgcrypto`, `unaccent`, `pg_trgm`, `pg_cron`, `pg_net`, `pgtap` | Dados no Brasil; RLS resolve tenant + minimização por time no banco; a agência já opera Supabase com MCP conectado. Projeto novo, separado do cliente "cozinha natural pet". |
| Edge Functions (Deno/TS) | `dispatch-events`, `whatsapp-send`, `whatsapp-webhook`, `journey-tick` (F2), `ai-assistant` (F2), `geocode` (F2) | Toda chamada com segredo roda aqui. Invocadas sempre com header `x-region: sa-east-1` (Database Webhook e `pg_net` incluem o header) para manter a execução no Brasil. |
| WhatsApp | Meta Cloud API (Graph API v21+), `lib/whatsapp/provider.ts` com `MetaCloudProvider` | Ver §8. |
| IA | `@anthropic-ai/sdk` nas Edge Functions; chave em Supabase Secrets | Ver §8. |
| CEP | ViaCEP (cliente + servidor), fallback BrasilAPI | Grátis, sem chave. |
| E-mail | Resend (SMTP custom do Supabase Auth + digest à central) | Free tier; domínio próprio com SPF/DKIM. |
| Hospedagem | Vercel (região `gru1`) + Supabase Cloud | Deploy por push na `main`; previews por PR; Supabase Branching para migrations. |
| Observabilidade (F1) | Logs do Supabase e da Vercel, `audit_log`, `ai_runs`, `message_log` | Sentry entra na Fase 2. |
| Qualidade/CI | pnpm, Biome, Vitest (regras de roteamento, E.164, máquina de estados), Playwright (cadastro offline → sync), pgTAP (RLS por papel × tabela + isolamento de 2ª unidade), GitHub Actions (`supabase db lint`, `db push`) | pgTAP é obrigatório: LGPD depende das policies. |

Fornecedores no MVP: Supabase, Vercel, Meta, Anthropic, Resend (5). Google e Sentry: Fase 2.

Estrutura do repositório:

```
app/            (campo)/ (central)/ (admin)/ api/
components/  lib/  lib/whatsapp/  lib/domain/  (zod schemas, routing puro, state machines)
supabase/migrations/  supabase/functions/  supabase/seed.sql  supabase/tests/ (pgTAP)
docs/adr/  docs/lgpd/  docs/ops/
```

---

## 2. Arquitetura

### 2.1 Componentes

1. **PWA do evangelista** — login, tela "Nova pessoa", fila offline, "Meus cadastros" (30 dias).
2. **Painel `/central`** — feed em tempo real, filas por time (modo central única), ficha da pessoa com timeline, contagem por bairro, conversas (F2). **`/admin`** — usuários/convites, regras de roteamento, templates, textos de consentimento, configurações da unidade.
3. **Postgres** — fonte da verdade; RLS; triggers (normalização, outbox, `updated_at`); RPCs `security definer` para transições de estado.
4. **Outbox + dispatcher** — `AFTER INSERT ON people` grava `outbox_events`; Database Webhook (INSERT) chama `dispatch-events`; `pg_cron` a cada 2 min reprocessa `status='pending'` com `attempts < 5`.
5. **Edge Functions** — `dispatch-events` (roteamento, classificação Haiku, notificações, agendamento do opt-in), `whatsapp-send` (worker de `message_log.status='queued'`, checa consentimento e quiet hours), `whatsapp-webhook` (assinatura, `wa_inbound_events`, statuses, botões, `SAIR`), `journey-tick` (F2, `pg_cron` a cada 15 min).
6. **Meta Cloud API** — WABA do Transtornar, 1 número por unidade (`units.whatsapp_phone_number_id`).
7. **Anthropic API** — só de Edge Functions, entrada pseudonimizada.

### 2.2 Diagrama

```
[Evangelista PWA] --offline--> IndexedDB (client_uuid)
      | online: rpc register_person(payload)  (anon key + JWT, RLS)
      v
[Postgres sa-east-1]
  people + people_contacts + children + needs + consents + households
  trigger -> outbox_events('person.registered')
      | Database Webhook (x-region: sa-east-1)          pg_cron 2 min (retry)
      v                                                        |
[Edge dispatch-events] <---------------------------------------+
  1. bairro já normalizado (select); CEP -> ViaCEP só valida
  2. households: cria/vincula por address_hash; flag duplicate_household
  3. Haiku: classifica needs.raw_text -> need_type[]; case_summary (2 linhas)
  4. routing_rules -> referrals (basic_food; outros inativos); fallback central
  5. notifications -> Realtime (painel) + template UTILITY interno p/ central + digest e-mail 20h
  6. message_log(queued, scheduled_for = now()+10min dentro de 08-21h) template opt-in
      v
[Edge whatsapp-send] --Graph API--> [WhatsApp da pessoa]
      ^ message_log sent/delivered/read/failed          | botão / texto / SAIR
      |                                                 v
[Edge whatsapp-webhook] <--X-Hub-Signature-256-- Meta
  raw -> wa_inbound_events (idempotente por wamid) -> processamento assíncrono
  "Quero receber" -> consents.confirmed_at + person_journeys.active + envia vídeo 1 (janela 24h)
  "Agora não"     -> journey paused (1 reenvio em 7 dias)
  "SAIR"          -> opt_out_person()
  texto livre     -> F1: resposta fixa + referral follow_up | F2: Haiku intent -> Sonnet / escalonamento
      v
[Painel /central] Realtime: feed, filas, ficha, v_conversions_by_neighborhood
```

### 2.3 Fluxo ponta a ponta (Fase 1)

1. Evangelista preenche o formulário (§5). O cliente gera `client_uuid`, normaliza telefone (E.164) e chama `register_person(payload jsonb)`. Sem sinal: fila Dexie, reenvio automático com o mesmo `client_uuid` (`ON CONFLICT (client_uuid) DO NOTHING`).
2. `register_person` (security definer, `unit_id` do JWT, nunca do body): insere `people`, `people_contacts`, `children`, `needs`, `consents` numa transação; se `phone_hash` já existe na unidade, grava `review_status='possible_duplicate'`, `duplicate_of_person_id` e **não** agenda jornada; cria/vincula `household` por `address_hash`; grava `person_events('registered')`.
3. Trigger → `outbox_events`. `dispatch-events`: roteia (§6), classifica texto livre, cria `notifications`, enfileira o template de opt-in em `message_log` com `scheduled_for`.
4. `whatsapp-send` só envia se existir `consents(purpose='whatsapp_contact', granted=true, revoked_at is null)` e a pessoa não for menor sem responsável; respeita `units.settings.quiet_hours` e o teto mensal de mensagens da unidade.
5. Webhook processa botões/status; "Quero receber" abre a janela e dispara o vídeo 1 como mídia (sem template).
6. Painel mostra o feed ("Mais uma pessoa aceitou Jesus no Xaxim — João — precisa de alimento"), a fila de cesta básica e a contagem por bairro.

---

## 3. Estratégia multi-tenant (franquia)

- `units` (cidade/franquia) é o tenant. `unit_id uuid not null references units(id)` em toda tabela operacional desde a migration 001. Curitiba semeada como única unidade ativa.
- Referência geográfica **global**: `cities` e `neighborhoods` sem `unit_id` (fonte IBGE/IPPUC); `unit_neighborhoods` define a cobertura de cada unidade (permite região metropolitana — Colombo, São José dos Pinhais — e mais de uma unidade na mesma cidade sem duplicar bairros).
- Catálogos com `unit_id` nullable (`null` = padrão global clonável): `content_assets`, `journey_steps`, `routing_rules`, `message_templates`, `reward_rules` (F2).
- `units.whatsapp_phone_number_id`, `whatsapp_waba_id`, `timezone`, `locale`, `settings` (quiet hours, cut-off, teto de mensagens, limiar de evento padrão).
- JWT: Custom Access Token Hook injeta `app_metadata.unit_id`, `role`, `team_ids[]`; policies leem `auth.jwt()`, sem subselect em `profiles`.
- `global_admin` (`unit_id` null) tem leitura em todas as unidades; escrita apenas em `units` e catálogos globais; toda leitura registrada em `audit_log`.
- Função `clone_unit_defaults(new_unit_id)` existe desde a 001 (clona catálogos globais para a nova unidade); UI de gestão de unidades é Fase 4.
- Strings da UI em `messages/pt-BR.json` desde o início (next-intl), sem tradução agora. Telefone E.164; endereço com `country_code`.
- CI: teste pgTAP que cria uma 2ª unidade fictícia, insere pessoas nas duas e prova que cada papel só enxerga a sua.

---

## 4. Modelo de dados

Convenções: `id uuid primary key default gen_random_uuid()`, `created_at timestamptz not null default now()`, `updated_at timestamptz not null default now()` (trigger `set_updated_at`). Enums como `text` + `check` (migráveis sem `alter type`). Chaves em inglês; textos da UI em pt-BR. Somente as migrations 001–006 são aplicadas na Fase 1; F2/F3 aparecem em §4.8 como esboço a versionar depois da reunião de validação.

### 4.1 Migration 001 — extensões, tenancy, geografia

```sql
create extension if not exists pgcrypto;
create extension if not exists unaccent;
create extension if not exists pg_trgm;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table units (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,                    -- 'curitiba'
  name text not null,
  country_code char(2) not null default 'BR',
  timezone text not null default 'America/Sao_Paulo',
  locale text not null default 'pt-BR',
  whatsapp_phone_number_id text, whatsapp_waba_id text, whatsapp_display_name text,
  settings jsonb not null default '{
    "quiet_hours": {"start": "21:00", "end": "08:00"},
    "first_contact_delay_minutes": 10,
    "monthly_message_cap": 5000,
    "same_day_cutoff": "14:00",
    "central_hours": {"weekdays": "09:00-18:00"},
    "marketing_throttle": 1.0 }',
  active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Referência global (IBGE/IPPUC); sem unit_id
create table cities (
  id uuid primary key default gen_random_uuid(),
  name text not null, state char(2) not null, country_code char(2) not null default 'BR',
  ibge_code text unique,
  unique (name, state, country_code)
);
create table neighborhoods (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references cities(id),
  name text not null,
  normalized_name text not null,                -- unaccent(lower(name))
  aliases text[] not null default '{}',         -- {'chaxim','chachim'} -> Xaxim
  region text,                                  -- regional administrativa
  unique (city_id, normalized_name)
);
create index neighborhoods_trgm_idx on neighborhoods using gin (normalized_name gin_trgm_ops);

create table unit_neighborhoods (               -- cobertura de cada unidade
  unit_id uuid not null references units(id),
  neighborhood_id uuid not null references neighborhoods(id),
  primary key (unit_id, neighborhood_id)
);

create table app_settings (                     -- chave/valor por unidade (texto de consentimento vigente etc.)
  unit_id uuid not null references units(id), key text not null, value jsonb not null,
  updated_at timestamptz not null default now(), primary key (unit_id, key)
);
```

### 4.2 Migration 002 — acesso, papéis, times

```sql
create table profiles (                          -- 1:1 com auth.users
  id uuid primary key references auth.users(id) on delete cascade,
  unit_id uuid references units(id),             -- null apenas para global_admin
  full_name text not null,
  phone_e164 text,                               -- opt-in para notificações internas
  role text not null check (role in ('evangelist','central','team_member','unit_admin','global_admin')),
  active boolean not null default true,
  volunteer_terms_version text, volunteer_terms_accepted_at timestamptz,   -- termo do voluntário (LGPD)
  internal_whatsapp_opt_in_at timestamptz,
  invited_by uuid references profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table invites (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  email text not null, role text not null, team_id uuid,
  code text unique not null,                     -- código curto no link de convite
  invited_by uuid references profiles(id), expires_at timestamptz not null, accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table teams (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  kind text not null check (kind in ('central','basic_food','home_items','education','employment','follow_up','logistics')),
  name text not null,
  notify_email text,
  active boolean not null default false,         -- MVP: central, basic_food, follow_up = true
  fallback_to_central boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (unit_id, kind)
);
create table team_members (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  team_id uuid not null references teams(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('member','lead','instructor','driver')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (team_id, profile_id)
);

-- Claims no JWT
create or replace function public.custom_access_token_hook(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p record; claims jsonb; tids uuid[];
begin
  select unit_id, role into p from profiles where id = (event->>'user_id')::uuid and active;
  select coalesce(array_agg(team_id), '{}') into tids from team_members
    where profile_id = (event->>'user_id')::uuid and active;
  claims := coalesce(event->'claims', '{}'::jsonb);
  claims := jsonb_set(claims, '{app_metadata}', coalesce(claims->'app_metadata','{}'::jsonb)
            || jsonb_build_object('unit_id', p.unit_id, 'role', p.role, 'team_ids', to_jsonb(tids)));
  return jsonb_set(event, '{claims}', claims);
end $$;

create or replace function auth_unit_id() returns uuid language sql stable as
  $$ select nullif(auth.jwt()->'app_metadata'->>'unit_id','')::uuid $$;
create or replace function auth_role() returns text language sql stable as
  $$ select auth.jwt()->'app_metadata'->>'role' $$;
create or replace function auth_team_ids() returns uuid[] language sql stable as
  $$ select coalesce(array(select jsonb_array_elements_text(auth.jwt()->'app_metadata'->'team_ids'))::uuid[], '{}') $$;
create or replace function is_unit_staff() returns boolean language sql stable as
  $$ select auth_role() in ('central','unit_admin','global_admin') $$;
```

### 4.3 Migration 003 — pessoa, PII separada, domicílio, filhos, necessidades, consentimento

```sql
create table households (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  address_hash text not null,                    -- sha256(normalize(street|number|complement|postal_code))
  neighborhood_id uuid references neighborhoods(id),
  city_id uuid references cities(id),
  adults_count smallint, children_count smallint,
  merged_into_id uuid references households(id),
  notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (unit_id, address_hash)
);

-- Fato + dados operacionais (sem PII direta)
create table people (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  client_uuid uuid not null unique,              -- idempotência offline
  phone_hash text not null,                      -- sha256(phone_e164 + pepper) para dedup/índices
  household_id uuid references households(id),
  neighborhood_id uuid not null references neighborhoods(id),
  city_id uuid not null references cities(id),
  age_range text check (age_range in ('under_18','18_24','25_34','35_49','50_64','65_plus')),
  has_basic_need boolean not null default false,
  children_count smallint not null default 0 check (children_count between 0 and 15),
  needs_job boolean, occupation_area text, wants_training boolean,
  income_range text check (income_range in ('none','up_to_1_mw','1_2_mw','2_5_mw','5_10_mw','over_10_mw','prefer_not')), -- F2 via WhatsApp
  profile_segment text,                          -- F2
  attends_church boolean,
  stage text not null default 'registered' check (stage in
    ('registered','optin_pending','journey_active','day7_done','day16_done','church_connected','supporter','paused','inactive','opted_out','anonymized')),
  stage_changed_at timestamptz not null default now(),
  decided_at timestamptz not null default now(),
  source text not null default 'street' check (source in ('street','event','legacy_platform','referral','import')),
  source_event_id uuid,                          -- FK events (F3)
  registered_by uuid not null references profiles(id),
  duplicate_of_person_id uuid references people(id),
  review_status text not null default 'ok' check (review_status in ('ok','possible_duplicate','merged')),
  observation text,                              -- texto curto do evangelista (restrito)
  case_summary text,                             -- gerado pela IA (restrito)
  consent_text_version text not null,
  last_contact_at timestamptz, anonymized_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index people_phone_primary_uidx on people (unit_id, phone_hash)
  where review_status = 'ok' and anonymized_at is null;
create index people_unit_nbh_decided_idx on people (unit_id, neighborhood_id, decided_at);
create index people_unit_stage_idx on people (unit_id, stage);
create index people_household_idx on people (household_id);

-- PII (RLS mais restrita; apagada na anonimização)
create table people_contacts (
  person_id uuid primary key references people(id) on delete cascade,
  unit_id uuid not null references units(id),
  full_name text not null,
  phone_e164 text not null,
  phone_owner text not null default 'self' check (phone_owner in ('self','family','other')),
  contact_name text,                             -- quando phone_owner <> self
  email text,
  address_kind text not null default 'fixed' check (address_kind in ('fixed','no_number','occupation','no_fixed_address')),
  street text, number text, complement text, postal_code text, address_raw text,
  guardian_name text, guardian_phone_e164 text,  -- obrigatórios se age_range = under_18
  whatsapp_valid boolean,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table children (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  age_band text not null check (age_band in ('0_5','6_11','12_14','15_17','18_plus')),
  created_at timestamptz not null default now()
);

create table needs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  household_id uuid references households(id),
  need_type text not null check (need_type in ('food','furniture','appliance','clothing','health','job','training','other')),
  item_code text,                                -- bed, sofa, stove, fridge, washing_machine
  raw_text text,
  detected_by text not null default 'evangelist' check (detected_by in ('evangelist','ai','team','person')),
  ai_confidence numeric(3,2),
  status text not null default 'open' check (status in ('open','routed','in_assistance','fulfilled','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table consents (                          -- append-only; histórico por versão
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  purpose text not null check (purpose in ('spiritual_followup','social_assistance','whatsapp_contact','marketing_events','share_with_church','share_with_employer','education_minor')),
  granted boolean not null,
  consent_text_version text not null,
  granted_at timestamptz not null default now(),
  given_via text not null check (given_via in ('evangelist_app','whatsapp_button','whatsapp_text','admin')),
  collected_by uuid references profiles(id),      -- evangelista testemunha
  given_by text not null default 'self' check (given_by in ('self','guardian')),
  confirmed_at timestamptz, confirmation_wamid text,  -- clique "Quero receber"
  revoked_at timestamptz, revoke_reason text,
  evidence jsonb,
  unique (person_id, purpose, consent_text_version)
);

-- Contagem anônima de decisões sem cadastro (recusa de dados) — preserva a métrica por bairro
create table decision_tally (
  id bigserial primary key,
  unit_id uuid not null references units(id),
  neighborhood_id uuid not null references neighborhoods(id),
  registered_by uuid not null references profiles(id),
  decided_on date not null default current_date,
  count int not null default 1,
  unique (unit_id, neighborhood_id, registered_by, decided_on)
);

create table person_events (                     -- timeline append-only
  id bigserial primary key,
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  event_type text not null,                      -- registered, referral_created, message_sent, optin_confirmed, opted_out, stage_changed, ...
  actor_profile_id uuid, payload jsonb not null default '{}',
  occurred_at timestamptz not null default now()
);
create index person_events_person_idx on person_events (person_id, occurred_at desc);
```

### 4.4 Migration 004 — roteamento, filas, outbox, notificações

```sql
create table routing_rules (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units(id),             -- null = padrão global (clonável)
  name text not null, priority int not null default 100,
  condition jsonb not null,                      -- {"need_type":"food"} | {"children_age_band_in":["12_14","15_17"]} | {"needs_job":true}
  target_team_kind text not null,
  referral_type text not null check (referral_type in ('basic_food','home_items','education','employment','follow_up','reward_delivery','church_connection','other')),
  auto_triage boolean not null default false,    -- true = vai direto ao time sem confirmação da central
  active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table referrals (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  household_id uuid references households(id),
  need_id uuid references needs(id),
  child_id uuid references children(id),
  team_id uuid not null references teams(id),
  referral_type text not null,
  rule_id uuid references routing_rules(id),
  reason text not null,
  priority smallint not null default 2 check (priority between 1 and 3),
  status text not null default 'new' check (status in ('new','triaged','in_progress','waiting','done','cancelled')),
  flags text[] not null default '{}',            -- duplicate_household, ai_suggested, minor
  assigned_to uuid references profiles(id), assigned_at timestamptz,
  due_at timestamptz, first_response_at timestamptz, done_at timestamptz,
  outcome text, cancelled_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index referrals_queue_idx on referrals (unit_id, team_id, status, created_at);

create table referral_events (                   -- append-only
  id bigserial primary key,
  unit_id uuid not null references units(id),
  referral_id uuid not null references referrals(id) on delete cascade,
  from_status text, to_status text not null, actor_profile_id uuid, note text,
  at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  recipient_profile_id uuid references profiles(id), team_id uuid references teams(id),
  kind text not null,                            -- person_registered, referral_new, delivery_failed, ai_escalation, daily_digest
  title text not null, body text, ref_table text, ref_id uuid,
  channels text[] not null default '{web}',      -- web | whatsapp | email
  sent_at timestamptz, read_at timestamptz,
  created_at timestamptz not null default now()
);

create table outbox_events (
  id bigserial primary key,
  unit_id uuid not null references units(id),
  event_type text not null,                      -- person.registered, need.created, message.status, journey.step_due
  aggregate_table text not null, aggregate_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','processing','done','failed')),
  attempts int not null default 0, next_attempt_at timestamptz not null default now(),
  last_error text, processed_at timestamptz,
  created_at timestamptz not null default now()
);
create index outbox_pending_idx on outbox_events (next_attempt_at) where status = 'pending';

create or replace function enqueue_person_registered() returns trigger language plpgsql as $$
begin
  insert into outbox_events (unit_id, event_type, aggregate_table, aggregate_id, payload)
  values (new.unit_id, 'person.registered', 'people', new.id,
          jsonb_build_object('person_id', new.id, 'review_status', new.review_status));
  return new;
end $$;
create trigger people_outbox after insert on people for each row execute function enqueue_person_registered();
```

### 4.5 Migration 005 — WhatsApp, conteúdo, jornada, mensagens, IA

```sql
create table content_assets (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units(id),             -- null = global
  title text not null, description text,
  media_type text not null check (media_type in ('video','image','document','link')),
  storage_path text, external_url text,
  wa_media_id text, wa_media_uploaded_at timestamptz,   -- reuso na Cloud API (renovar a cada 30 dias)
  duration_seconds int, size_bytes bigint,
  source text not null default 'new' check (source in ('new','legacy_platform')),
  transcript text,                               -- base de conhecimento da IA (F2)
  audience_segment text not null default 'all',
  rights_ok boolean not null default false, wa_compatible boolean,
  active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table message_templates (                 -- espelho dos templates aprovados na Meta
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units(id),
  name text not null, language text not null default 'pt_BR',
  category text not null check (category in ('UTILITY','MARKETING','AUTHENTICATION')),
  meta_template_id text, status text not null default 'pending' check (status in ('pending','approved','rejected','paused')),
  header_type text, body_text text not null, buttons jsonb not null default '[]', variables jsonb not null default '[]',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (unit_id, name, language)
);

create table journey_steps (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units(id),             -- null = jornada padrão global
  journey_key text not null default 'first_steps',
  sequence int not null, day_offset int not null,   -- dias após optin_confirmed_at; passo 0 = opt-in
  send_hour smallint not null default 19,
  content_asset_id uuid references content_assets(id),
  template_name text,                            -- usado só se a janela de 24h estiver fechada
  message_text text not null,
  buttons jsonb not null default '[]',
  ask_feedback boolean not null default true,
  counts_as_content_day boolean not null default true,
  audience_segment text not null default 'all',
  active boolean not null default true,
  unique (unit_id, journey_key, sequence, audience_segment)
);

create table person_journeys (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  journey_key text not null default 'first_steps',
  status text not null default 'scheduled' check (status in ('scheduled','awaiting_optin','active','paused','completed','opted_out','failed')),
  current_sequence int not null default 0,
  optin_sent_at timestamptz, optin_confirmed_at timestamptz, optin_reminder_sent_at timestamptz,
  next_send_at timestamptz, last_sent_at timestamptz, completed_at timestamptz,
  completed_content_days int not null default 0,
  pause_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (person_id, journey_key)
);

create table journey_progress (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_journey_id uuid not null references person_journeys(id) on delete cascade,
  step_id uuid not null references journey_steps(id),
  sent_at timestamptz, delivered_at timestamptz, read_at timestamptz,
  watched_confirmed_at timestamptz, completion_source text check (completion_source in ('button','ai_inferred','manual')),
  feedback_choice text, feedback_text text, feedback_sentiment text,
  reminder_count smallint not null default 0,
  unique (person_journey_id, step_id)
);

create table message_log (                       -- outbound
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid references people(id) on delete set null,
  profile_id uuid references profiles(id),       -- destinatário interno
  to_phone_hash text not null,
  kind text not null check (kind in ('template','interactive','text','media')),
  template_name text, step_id uuid references journey_steps(id),
  provider text not null default 'meta_cloud',
  provider_message_id text unique,               -- wamid
  status text not null default 'queued' check (status in ('queued','sent','delivered','read','failed','skipped')),
  skip_reason text, error_code text, error_message text,
  pricing_category text,                         -- utility | marketing | service (do webhook)
  cost_estimate numeric(8,4),
  payload jsonb,
  scheduled_for timestamptz not null default now(),
  queued_at timestamptz not null default now(), sent_at timestamptz, delivered_at timestamptz, read_at timestamptz
);
create index message_log_queue_idx on message_log (scheduled_for) where status = 'queued';

create table wa_inbound_events (                 -- cru, idempotente
  id uuid primary key default gen_random_uuid(),
  wamid text unique, phone_number_id text not null, wa_id text,
  event_type text not null check (event_type in ('message','status','error','quality_update','template_update')),
  raw jsonb not null,
  processed_at timestamptz, error text,
  received_at timestamptz not null default now()
);

create table conversations (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid not null references people(id) on delete cascade,
  window_open_until timestamptz,
  mode text not null default 'ai' check (mode in ('ai','human','paused')),
  assigned_to uuid references profiles(id),
  last_inbound_at timestamptz, last_outbound_at timestamptz, unread_count int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (person_id)
);
create table messages (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  conversation_id uuid not null references conversations(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound')),
  author_type text not null check (author_type in ('person','ai','human','system')),
  author_profile_id uuid,
  content_type text not null,                    -- text, button, audio, image, video, unsupported
  body text, button_payload text, media_path text,
  ai_intent text, ai_confidence numeric(3,2), ai_model text,
  wamid text unique,
  created_at timestamptz not null default now()
);
create index messages_conv_idx on messages (conversation_id, created_at desc);

create table ai_runs (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  kind text not null check (kind in ('classify_need','case_summary','classify_inbound','assistant_turn','feedback_classify','weekly_digest','job_match')),
  model text not null, person_id uuid, ref_table text, ref_id uuid,
  input_tokens int, output_tokens int, cache_read_tokens int,
  cost_usd numeric(10,6), latency_ms int,
  output jsonb, status text not null default 'ok', error text,
  created_at timestamptz not null default now()
);
```

### 4.6 Migration 006 — auditoria, LGPD, RPCs, views

```sql
create table audit_log (                         -- append-only
  id bigserial primary key,
  unit_id uuid, actor_id uuid, actor_role text,
  action text not null, table_name text not null, row_id uuid,
  diff jsonb, ip inet,
  created_at timestamptz not null default now()
);
create table data_requests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id),
  person_id uuid references people(id),
  request_type text not null check (request_type in ('access','deletion','correction','portability','revoke_consent')),
  received_via text not null, received_at timestamptz not null default now(),
  due_at timestamptz not null default now() + interval '15 days',
  fulfilled_at timestamptz, handled_by uuid references profiles(id), note text
);

-- RPCs (security definer, search_path fixo; sempre validam auth_unit_id())
-- register_person(payload jsonb) -> jsonb {person_id, review_status}
-- referral_transition(referral_id uuid, to_status text, note text)
-- opt_out_person(phone_hash text, reason text)
-- confirm_optin(person_id uuid, wamid text)
-- open_person_record(person_id uuid) -> registra leitura em audit_log e devolve a ficha permitida ao papel
-- anonymize_person(person_id uuid, reason text)
-- merge_people(primary_id uuid, duplicate_id uuid)       (central)
-- record_decision_tally(neighborhood_id uuid)            (evangelista; sem PII)
-- clone_unit_defaults(new_unit_id uuid)

-- Views
create view v_conversions_by_neighborhood with (security_invoker = true) as
  select p.unit_id, n.id as neighborhood_id, n.name as neighborhood,
         date_trunc('week', p.decided_at) as week, p.stage, count(*) as people
  from people p join neighborhoods n on n.id = p.neighborhood_id
  where p.review_status <> 'merged'
  group by 1,2,3,4,5;

create view v_decisions_total_by_neighborhood with (security_invoker = true) as   -- cadastrados + recusas anônimas
  select unit_id, neighborhood_id, sum(c) as decisions from (
    select unit_id, neighborhood_id, count(*) c from people where review_status <> 'merged' group by 1,2
    union all select unit_id, neighborhood_id, sum(count) from decision_tally group by 1,2) t
  group by 1,2;

create view v_team_basic_food with (security_invoker = true) as   -- colunas mínimas para o time de cesta
  select r.id as referral_id, r.status, r.priority, r.flags, r.created_at, r.assigned_to,
         c.full_name, c.phone_e164, c.address_kind, c.street, c.number, c.complement,
         n.name as neighborhood, p.children_count, p.household_id
  from referrals r join teams t on t.id = r.team_id and t.kind = 'basic_food'
  join people p on p.id = r.person_id join people_contacts c on c.person_id = p.id
  join neighborhoods n on n.id = p.neighborhood_id;

create view v_impact_public with (security_invoker = true) as     -- agregados com k-anonimato
  select unit_id, neighborhood_id, date_trunc('month', decided_at) as month, count(*) as people
  from people where review_status <> 'merged' group by 1,2,3 having count(*) >= 5;

-- Jobs
select cron.schedule('outbox-retry', '*/2 * * * *', $$select net.http_post(...dispatch-events..., headers := '{"x-region":"sa-east-1"}')$$);
select cron.schedule('whatsapp-send', '* * * * *', $$select net.http_post(...whatsapp-send...)$$);
select cron.schedule('daily-digest', '0 23 * * *', $$select enqueue_daily_digest()$$);           -- 20h BRT
select cron.schedule('lgpd-retention', '0 6 1 * *', $$select run_retention_policy()$$);         -- mensal
```

### 4.7 RLS (resumo)

RLS habilitada em todas as tabelas. Toda policy começa por `unit_id = auth_unit_id()` (exceto `auth_role() = 'global_admin'`, leitura). `service_role` só em Edge Functions.

| Tabela | evangelist | team_member | central / unit_admin | global_admin |
|---|---|---|---|---|
| `people` | insert via RPC; select `registered_by = auth.uid()` e `created_at > now()-30d` (via view `v_my_registrations`: nome, bairro, estágio, status WhatsApp, selo de duplicidade) | select só por join com `referrals` do próprio time (`team_id = any(auth_team_ids())`) via `v_team_*`; sem `income_range`, `observation`, `case_summary` | tudo da unidade | leitura, com `audit_log` |
| `people_contacts` | insert via RPC; select telefone só por 30 dias (para corrigir número) | só via `v_team_*` (nome, telefone, endereço quando o tipo de demanda exige) | tudo | leitura |
| `children`, `needs` | insert via RPC | `education` vê `age_band`; `basic_food` vê `children_count` apenas | tudo | leitura |
| `consents`, `audit_log`, `data_requests`, `decision_tally` | insert via RPC | nenhum | central: leitura; unit_admin: leitura/insert | leitura |
| `referrals`, `referral_events` | nenhum | select/update onde `team_id = any(auth_team_ids())`; transição só via `referral_transition` | tudo | leitura |
| `conversations`, `messages`, `message_log` | status agregado via `v_my_registrations` | só time `follow_up` | tudo | leitura |
| `journey_*`, `outbox_events`, `wa_inbound_events`, `ai_runs`, `notifications` | nenhum / próprias notificações | próprias notificações | tudo | leitura |
| `units`, `cities`, `neighborhoods`, `unit_neighborhoods`, catálogos globais | leitura | leitura | leitura; unit_admin edita catálogos da própria unidade | escrita |

Testes pgTAP obrigatórios no CI: um por papel × tabela, mais `isolation_second_unit.sql`.

### 4.8 Esboço das migrations F2/F3 (não aplicar na Fase 1; validar com o cliente antes)

```sql
-- F2 assistência e logística
assistance_programs (id, unit_id, household_id, person_id, referral_id, program_type 'food_basket', start_date, end_date, frequency 'monthly',
  planned_deliveries 3, completed_deliveries 0, status active|ending_soon|completed|renewed|cancelled, renewed_from_id, approved_by)
  + unique index one_active_program_per_household (household_id, program_type) where status in ('active','ending_soon')
catalog_items (id, unit_id, code, name, category basket|furniture|appliance|reward|other, active)
inventory_stock (id, unit_id, catalog_item_id, location, on_hand, reserved)   inventory_movements (append-only)
delivery_orders (id, unit_id, household_id, person_id, referral_id, assistance_program_id, sequence_no, status scheduled|picking|packed|out_for_delivery|delivered|failed|cancelled,
  scheduled_date, same_day_target, requested_at, dispatched_at, delivered_at, failure_reason, attempt_no, driver_member_id, address_snapshot jsonb, proof_photo_path, recipient_name)
delivery_order_items (delivery_order_id, catalog_item_id, qty)
sla_policies (id, unit_id, referral_type, first_response_hours, resolution_hours, business_hours_only, escalate_to_role)
follow_ups (id, unit_id, person_id, member_id, kind note|call|visit|escalation|prayer_request|crisis, note, next_action_at, done_at, created_by human|ai|system)
-- F2 igrejas, educação, trabalho
churches (id, unit_id, name, neighborhood_id, address, contact_name, contact_phone_e164, active)
church_connections (id, unit_id, person_id, church_id, status suggested|invited|visited|connected|declined, shared_with_church_at, consent_id)
courses (id, unit_id, name, audience teen|adult, area, provider, min_age, max_age, active)
course_classes (id, unit_id, course_id, starts_on, ends_on, capacity, location, status)
course_instructors (course_class_id, team_member_id)   volunteer_availability (id, unit_id, team_member_id, weekday, time_slot, skills[])   -- só se R-31(a)
enrollments (id, unit_id, course_id, course_class_id, person_id, child_id, referral_id, status referred|enrolled|attending|completed|dropped|waitlist, certificate_path)
companies (id, unit_id, name, legal_id, legal_id_hash, roles[] employer|benefit_partner, sector, neighborhood_id, source manual|legacy_import, imported_at, last_openings_review_at, active)
  + unique (unit_id, legal_id_hash) where legal_id_hash is not null
company_contacts (id, unit_id, company_id, name, role, phone_e164, email, legal_basis 'legitimate_interest_b2b')
job_openings (id, unit_id, company_id, role_title, area, open_positions, requirements, status open|paused|filled|closed)
job_placements (id, unit_id, person_id, referral_id, job_opening_id, status profiling|matched|referred|interviewed|hired|not_hired|withdrawn, match_reason, outcome_at)
import_batches (id, unit_id, kind, file_path, rows_total, rows_ok, rows_rejected, report jsonb, run_by)
-- F2 gamificação (ambas as leituras de "pontos", sem migração futura)
reward_rules (id, unit_id, name, condition_type milestone_days|points_threshold|step_completed, condition_value int, catalog_item_id, message_text, active)
point_rules (id, unit_id, event_type, points, active)   points_ledger (id, unit_id, person_id, event_type, points, ref_id, earned_at)
reward_grants (id, unit_id, person_id, reward_rule_id, earned_at, notified_at, delivery_referral_id, delivered_at, unique(person_id, reward_rule_id))
-- F3 eventos, mantenedores, benefícios
events (id, unit_id, name, event_type neighborhood|business_owners|supporter_pitch|celebration, neighborhood_id, city_id, starts_at, venue, capacity, target_segment jsonb, threshold_reached_at, status)
event_thresholds (id, unit_id, neighborhood_id null=padrão, metric, threshold, alert_at_pct int[] '{50,80,100}', active)   -- id próprio (neighborhood_id é nullable)
event_invitations (id, unit_id, event_id, person_id, message_log_id, sent_at, rsvp, checked_in_at, unique(event_id, person_id))
supporters (id, unit_id, person_id null, external_name, origin transtornar|external, status prospect|invited|attended_pitch|active|paused|churned, plan, amount_cents, periodicity, since)
supporter_eligibility_rules (id, unit_id, condition jsonb, active)   contributions (id, unit_id, supporter_id, amount_cents, paid_at, external_ref, receipt_path)
benefits (id, unit_id, company_id, description, rules, valid_until, active)   benefit_redemptions (id, unit_id, supporter_id, benefit_id, redeemed_at, validated_by)
```

Regras para o esboço: nada de colunas `generated` com `now()` (não imutável); nenhuma PK com coluna nullable; `referral_type` referenciado só depois de definido; PostGIS não entra.

---

## 5. Formulário "Nova pessoa" (exato)

Uma tela obrigatória (~45-60 s) + seção recolhida "Mais detalhes" (~20 s). Chips e toggles no lugar de digitação; botão fixo "Registrar decisão"; nada que constranja na rua.

| # | Campo (label) | Coluna | UI | Obrig. | Consumidor |
|---|---|---|---|---|---|
| 1 | Nome | `people_contacts.full_name` | texto, autocapitalize; aceita só primeiro nome | Sim | Notificação à central; `{{1}}` do template |
| 2 | WhatsApp | `people_contacts.phone_e164` (+`people.phone_hash`) | máscara `(41) 9 9999-9999`, teclado numérico, Contact Picker onde houver; ao sair do campo consulta `phone_hash` → aviso "já cadastrado em DD/MM por X" (não bloqueia) | Sim | Jornada e dedup |
| 2a | O número é… | `phone_owner`, `contact_name` | chips: Da própria pessoa · De alguém da família · Outro (+ nome de quem atende) | Sim (default "própria") | Jornada vai para quem atende; dedup por casa |
| 3 | Faixa etária | `people.age_range` | chips: até 17 · 18-24 · 25-34 · 35-49 · 50-64 · 65+ | Sim | Segmentação; **gate de menor** |
| 3a | (se até 17) Responsável | `guardian_name`, `guardian_phone_e164` | nome + WhatsApp do responsável | Sim | Consentimento é do responsável; jornada vai ao responsável |
| 4 | Bairro | `people.neighborhood_id` | select com busca (cobertura da unidade), último bairro usado como padrão; CEP (opcional) preenche via ViaCEP | Sim | Métrica central, eventos, roteamento |
| 5 | Endereço | `address_kind`, `street`, `number`, `complement`, `postal_code` | chips de tipo: Casa com número · Sem número/fundos · Ocupação · Sem endereço fixo; campos rua/número/complemento aparecem conforme o tipo | Sim (rua + número para "Casa"; ponto de referência para os demais) | Entrega, domicílio (`address_hash`) |
| 6 | Precisa de algo em casa? | `people.has_basic_need`, `needs` | chips multi: Alimento · Móvel · Eletrodoméstico · Roupas · Saúde/remédio · Nada; sub-chips para móvel/eletro (cama, sofá, fogão, geladeira, máquina de lavar, outro) | Sim (pode ser "Nada") | Roteamento determinístico |
| 7 | Filhos | `people.children_count`, `children.age_band` | stepper 0-9; por filho, chip de faixa: 0-5 · 6-11 · 12-14 · 15-17 · 18+ | Sim (default 0) | Educação (F2); dimensionar cesta |
| 8 | Consentimento | `consents` (3 finalidades) + `people.consent_text_version` | roteiro de 2 linhas lido em voz alta + 1 checkbox + link "termo completo" | Sim (bloqueia salvar) | LGPD art. 11, I + opt-in Meta |
| — | **Mais detalhes (opcional)** | | recolhido | | |
| 9 | Trabalho | `needs_job`, `wants_training`, `occupation_area` | toggles "Precisa de trabalho?" / "Quer fazer curso?" + chips de área (cozinha, construção, limpeza, vendas, transporte, cuidados, administrativo, autônomo/empresário, outro) | Não | Time de trabalho (F2), identificação de perfil |
| 10 | Já frequenta alguma igreja? | `attends_church` | Sim / Não / Não sei | Não | Conexão com igreja (F2) |
| 11 | Algo que a central deve saber? | `people.observation` + `needs.raw_text` | texto até 140 caracteres | Não | Haiku classifica; resumo à central |
| 12 | E-mail | `people_contacts.email` | e-mail | Não | Sem consumidor descrito; por último |
| 13 | Aceitou em outra data? | `decided_at` | toggle discreto + data | Não | Marcos da jornada |

**Automáticos:** `unit_id` (JWT), `registered_by`, `decided_at = now()`, `source` (`street`, ou `event` em "modo evento"), `client_uuid`, `consent_text_version`, `city_id` (derivado do bairro), `household_id` (derivado do endereço). **Não coletados:** GPS do evangelista, renda (F2 via WhatsApp), CPF, data de nascimento, nome/gênero de filhos, foto.

**Recusa de dados:** botão secundário "A pessoa aceitou Jesus mas não quer se cadastrar" → `record_decision_tally(neighborhood_id)`; nenhuma PII, métrica preservada.

**Tela de sucesso:** "João registrado no Xaxim. Mensagem de boas-vindas agendada." (offline: "Salvo no aparelho — envia quando houver sinal") + "Cadastrar outra pessoa" + contador "3ª pessoa hoje". Mensagens nunca prometem entrega ou prazo.

**Validação em campo:** protótipo clicável (Figma/HTML estático) testado com 3 evangelistas na semana 1, antes das migrations de UI; meta: mediana ≤ 75 s na tela obrigatória, zero abandono por campo.

---

## 6. Roteamento

**Motor:** função pura `route(personSnapshot, rules) -> Referral[]` em `lib/domain/routing.ts` (testada com Vitest), executada por `dispatch-events` no evento `person.registered` e reexecutada em `need.created` (IA/WhatsApp/time descobre nova necessidade).

**Regras determinísticas semeadas (Curitiba):**

| Prioridade | Condição | Time | Tipo | auto_triage | Ativa no MVP |
|---|---|---|---|---|---|
| 10 | `need_type = food` | basic_food | basic_food | true | Sim |
| 20 | `need_type in (furniture, appliance)` | home_items | home_items | false | Não (cai na central) |
| 30 | `children.age_band in (12_14, 15_17)` | education | education | false | Não |
| 40 | `needs_job = true or wants_training = true` | employment | employment | false | Não |
| 50 | inbound de texto livre sem IA (F1) / `ai_intent in (help, crisis, prayer)` (F2) | follow_up | follow_up | true | Sim |
| 60 | `age_range = under_18` | central | other (flag `minor`) | true | Sim |

Regras: se o time-alvo tem `active=false` ou nenhum membro ativo, o referral entra com `team_id` da central (`fallback_to_central`). Se já existe referral aberto de `basic_food` no mesmo `household_id`, o novo nasce com flag `duplicate_household` para a central decidir (sem cesta dupla). **Estratégia não recebe referral**: consome `v_conversions_by_neighborhood`, painel e, na Fase 2, o digest semanal (Opus).

**IA (desde o MVP, só onde agrega):** quando `observation`/`raw_text` não vazio, `claude-haiku-4-5` com `output_config.format` (schema zod: `need_types[]`, `item_codes[]`, `urgency 1-3`, `tags[]`, `summary ≤ 240 chars`) — entrada pseudonimizada (sem nome/telefone/endereço; bairro + chips + texto). Saída vira `needs(detected_by='ai', ai_confidence)` e `people.case_summary`; referrals derivados de IA nascem com flag `ai_suggested` e `auto_triage=false`. Falha da API não bloqueia: roteamento por chips segue. Registro em `ai_runs` com custo; alerta se gasto diário > `units.settings.ai_daily_cap_usd`.

**Máquina de estados de referrals:** `new → triaged → in_progress → waiting → done`, `cancelled` de qualquer estado, reatribuição = novo referral com `parent` e original `cancelled(reassigned)`. Só via `referral_transition()` (valida transição, checa `auth_team_ids()`, grava `referral_events`, `first_response_at`, `done_at`). SLA automático com escalonamento: Fase 2 (`sla_policies`); no MVP o painel mostra "sem responsável há X h".

---

## 7. Jornada WhatsApp "Primeiros passos da vida com Deus"

### 7.1 Regras de envio
- Nada é enviado sem `consents(whatsapp_contact)` válido; menor sem responsável não recebe nada; `SAIR`/`PARAR`/`CANCELAR` (regra) → `opt_out_person` em < 1 min, confirmação única, nunca mais template.
- Quiet hours 21h-08h (por unidade); fora disso, agenda para 08h.
- Janela de 24 h (`conversations.window_open_until`) decide automaticamente: mídia/texto livre dentro da janela; template fora dela. Cada vídeo termina com botão, o que reabre a janela e reduz templates pagos.
- `WhatsAppProvider.sendTemplate` verifica consentimento, opt-out, teto mensal (`monthly_message_cap`) e `marketing_throttle` (reduzido automaticamente por `phone_number_quality_update`).
- Erros da Cloud API mapeados: `131026` (sem WhatsApp) → `people_contacts.whatsapp_valid=false` + selo em "Meus cadastros" para o evangelista corrigir; `131049/131050` → pausa marketing.

### 7.2 Sequência (jornada padrão global `first_steps`; dias contados a partir de `optin_confirmed_at`)

| Passo | Dia | Conteúdo | Template (fora da janela) | Botões | Fase |
|---|---|---|---|---|---|
| 0 | T+10 min do cadastro (08-21h) | **Opt-in neutro**: "Olá {{1}}! Aqui é o Transtornar. Hoje você conversou com {{2}} e ele(a) registrou seu contato. Quer receber nossas mensagens e vídeos? Você pode parar quando quiser respondendo SAIR." | `transtornar_optin_v1` (submeter como UTILITY; aceitar reclassificação) | **Quero receber** / **Agora não** | 1 |
| 0b | +48 h sem resposta | lembrete único, mesmo texto curto | `transtornar_optin_lembrete_v1` | idem | 1 |
| 1 | imediato após "Quero receber" | Vídeo 1 (importância de Jesus / primeiros passos), mídia na janela | — (`transtornar_video_v1` só como fallback) | **Assisti até o final** / **Ainda não** | 1 |
| 1f | após "Assisti" | "O que você achou?" | — | Me ajudou muito / Gostei / Fiquei com dúvida (+ texto livre) | 2 |
| 2 | D+2 | Vídeo 2 — oração | `transtornar_passo_v1` ("Seu vídeo de hoje está pronto") | **Ver o vídeo de hoje** → mídia na janela | 2 |
| 3 | D+4 | Vídeo 3 — Bíblia | idem | idem | 2 |
| 4 | D+7 | Vídeo 4 — comunidade/igreja + convite à igreja mais próxima (F2, `churches`) | idem | idem + **Quero conhecer uma igreja** | 2 |
| M1 | D+7 concluído (4 vídeos confirmados) | **Marco 1 → Bíblia** (`reward_rules milestone_days=7`) → `reward_grants` → referral `reward_delivery` | `transtornar_premio_v1` (UTILITY) | — | 2 |
| 5 | D+9 | Vídeo 5 — perdão | passo | idem | 2 |
| 6 | D+11 | Vídeo 6 — família/trabalho (coleta opcional de renda e interesse em curso por botões) | passo | idem + botões de renda "prefiro não dizer" | 2 |
| 7 | D+14 | Vídeo 7 — servir/próximos passos | passo | idem | 2 |
| 8 | D+16 | Vídeo 8 — encerramento + "Quer continuar recebendo?" | passo | **Quero continuar** / **Por enquanto não** | 2 |
| M2 | D+16 concluído (8 vídeos) | **Marco 2 → livrinho**; `stage='day16_done'`; mensagem de conquista | `transtornar_premio_v1` | — | 2 |
| Progresso | após cada confirmação | "Você completou 3 de 8 passos" (dentro da janela, grátis; máx. 1/dia) | — | — | 2 |

"7 dias de conteúdo" = vídeos confirmados pelo botão (não dias corridos); sem confirmação, um lembrete por passo (`reminder_count ≤ 1`) e o passo seguinte segue no calendário. `reward_rules.condition_type` já aceita `points_threshold` caso o cliente confirme a leitura de pontuação acumulada (`point_rules`/`points_ledger`).

### 7.3 Scheduler e conversa
- `journey-tick` (`pg_cron` a cada 15 min, F2): seleciona `person_journeys` com `next_send_at <= now()` e `status='active'`, escolhe o passo pelo `audience_segment`, enfileira em `message_log`, avança `next_send_at`.
- Texto livre no MVP: resposta fixa ("Recebemos sua mensagem; alguém do Transtornar vai te responder") + referral `follow_up`. Fase 2: `claude-haiku-4-5` classifica intenção (dúvida, ajuda, necessidade nova, oração, crise, opt-out, conversa) → `claude-sonnet-5` responde (persona, transcrições dos vídeos em prompt cacheado, `thinking: {type:"adaptive"}`, `output_config.effort: "low"`, tools `open_need`, `escalate_to_human`, `record_step_completion`, `record_feedback`, `update_person_field`, `suggest_church`); crise/tema pastoral profundo → `follow_ups(kind='crisis')` prioridade 1 e humano em ≤ 1 h; humano assume com `conversations.mode='human'`; kill switch por unidade.

---

## 8. Integrações

### 8.1 WhatsApp — Meta Cloud API oficial, direta

| Opção | Banimento | Custo | Veredito |
|---|---|---|---|
| **Cloud API (Meta) direta** | Nenhum por método de conexão; risco real é quality rating e pausa de templates | Só a tarifa Meta por mensagem; sem mensalidade | **Escolhida** |
| BSP (360dialog, Twilio) | Igual | Markup/mensalidade; inbox que o painel substitui | Plano B via `WhatsAppProvider` se a verificação da Meta travar |
| Z-API / Evolution (não oficiais) | Alto; disparo automatizado para números frios é o padrão banido | Baixo | **Proibida** (ADR-002) — perder o número = perder a base em jornada |

Operação: Business Manager, WABA e número **no nome do Transtornar** (CNPJ do controlador), agência como parceira; número dedicado; nome de exibição aprovado; 2FA; token de usuário de sistema; webhook com `X-Hub-Signature-256`; limite inicial de 250 conversas/24 h sobe com verificação; templates versionados em `message_templates` com categoria e status (pausa por reclassificação vira alerta); vídeos ≤ 16 MB H.264/AAC, upload único → `wa_media_id` (renovado a cada 30 dias) e cópia canônica no Storage (bucket privado, URL assinada); sem grupos (notificação interna por template UTILITY individual a membros com `internal_whatsapp_opt_in_at`).

**Preços:** a tabela da Meta muda (modelo por mensagem, categorias, cobrança dentro da janela). **Tarefa da Fase 0: verificar a tabela vigente para o Brasil, registrar em `docs/ops/whatsapp-pricing.md` com data, e definir `monthly_message_cap`.** Fórmula de orçamento: `custo_por_pessoa ≈ n_templates_marketing × tarifa_marketing + n_templates_utility × tarifa_utility` (desenho atual: 1-2 utility + ≤ 7 marketing por pessoa, o restante dentro da janela).

### 8.2 IA — Anthropic API

| Uso | Modelo | Fase | Notas |
|---|---|---|---|
| Classificar `observation`/`raw_text` → `needs`, urgência, resumo de 2 linhas | `claude-haiku-4-5` | 1 | Structured outputs (`output_config.format`), `max_tokens ~512`, sem thinking; entrada pseudonimizada; fallback determinístico |
| Classificar intenção/sentimento de inbound e feedback | `claude-haiku-4-5` | 2 | síncrono para inbound, batch diário para feedback |
| Assistente no WhatsApp Transtornar | `claude-sonnet-5` | 2 | tool use, `thinking: {type:"adaptive"}`, `effort: low`, prompt caching (persona + transcrições) |
| Digest semanal para estratégia por bairro/segmento; matching pessoa ↔ vaga/curso com justificativa (sugere, humano confirma) | `claude-opus-5` | 2/3 | Message Batches (50% de desconto), dados agregados/pseudonimizados |

Preços de referência (tabela Anthropic, US$/MTok entrada/saída): Haiku 4.5 1/5; Sonnet 5 2/10; Opus 5 5/25 — confirmar na tabela vigente. Custo por cadastro (Haiku) < US$0,002. Regras: chamadas só de Edge Functions; nunca enviar nome, telefone, endereço ou nome de menor; `ai_runs` registra modelo, tokens, custo e latência; teto diário por unidade; contrato/DPA e política de retenção da API registrados em `docs/lgpd/operadores.md` (transferência internacional, art. 33). `claude-fable-5-1` não é usado.

### 8.3 CEP e bairro
ViaCEP (cliente + servidor) com fallback BrasilAPI; o bairro retornado é casado com `neighborhoods` por `normalized_name`/`aliases` + `pg_trgm` (similaridade ≥ 0,6); sem match, o select do evangelista prevalece. Google Geocoding (lat/lng, reverse para "usar minha localização" da pessoa) entra na Fase 2 com a logística; links de navegação `google.com/maps/dir/?api=1&destination=` sem custo.

### 8.4 E-mail e outros
Resend: SMTP do Supabase Auth (convites, redefinição de senha) + digest diário da central às 20h + alertas (quality rating, template pausado, teto de mensagens). Nenhum e-mail ao convertido. Fase 2: Sentry, Google Geocoding, Storage de comprovantes. Notion (MCP): página do projeto com decisões e perguntas em aberto (documentação, não integração de produto).

---

## 9. LGPD

**Natureza e base legal**

| Dado | Classificação | Base legal | Registro |
|---|---|---|---|
| Existência em `people` (aceitou Jesus) | Sensível — convicção religiosa (art. 5º, II) | Consentimento específico e destacado (art. 11, I); sem legítimo interesse | `consents(spiritual_followup)` |
| Nome, telefone, endereço, e-mail, faixa etária, necessidades, trabalho | Pessoal (vulnerabilidade social) | Mesmo consentimento, finalidades explícitas | `consents(social_assistance, whatsapp_contact)` |
| Renda | Pessoal, delicado | Consentimento; pergunta opcional com "prefiro não dizer" (F2, WhatsApp) | — |
| Filhos (faixa etária, sem nome) | Dado de menor (art. 14) | Consentimento do responsável (o próprio cadastrado) | matrícula: `consents(education_minor)` |
| Pessoa cadastrada com até 17 anos | Sensível de menor | Consentimento do responsável legal **antes** de gravar PII; jornada vai ao responsável | `consents.given_by='guardian'` |
| Conversas no WhatsApp | Pessoal, potencialmente sensível | Consentimento de comunicação | retenção 12 meses |
| Evangelistas, membros de time | Pessoal (voluntário) | Termo de voluntariado (`profiles.volunteer_terms_*`), opt-in para notificações internas; **sem GPS** | — |
| Contatos de empresas (F2) | Pessoal | Legítimo interesse B2B com finalidade registrada | `company_contacts.legal_basis` |
| Pessoas da plataforma legada (F2) | Sensível | Só entram na base após consentimento equivalente obtido por contato humano; até lá, apenas inventário | `source='legacy_platform'` |

**Papéis:** controlador = pessoa jurídica do Transtornar (CNPJ e DPO definidos na Fase 0 — **gate contratual**); operadora = High Ground (contrato com sub-operadores listados: Supabase, Vercel, Meta, Anthropic, Resend; Google e Sentry na F2). Banco em sa-east-1; Edge Functions invocadas em sa-east-1; Meta e Anthropic processam fora do país com minimização e registro (art. 33). RIPD (`docs/lgpd/ripd.md`) entregue na Fase 1.

**Consentimento:** roteiro lido em voz alta + checkbox + versão do texto (`consent_text_version`, `given_at`, `collected_by`, `client_uuid`); dupla confirmação pelo próprio titular no botão "Quero receber" (`confirmed_at`, `confirmation_wamid`). O primeiro template é neutro e não revela convicção religiosa (número errado ou compartilhado não expõe dado sensível). Sem checkbox, o app não grava PII — grava só `decision_tally`. Consentimentos adicionais (igreja, empresa, eventos) sempre por botão no WhatsApp, nunca presumidos.

**Minimização por papel:** PII em `people_contacts`; views por time expõem só o necessário (cesta: nome, telefone, endereço, composição familiar; educação: faixa dos filhos + contato do responsável; trabalho: área + contato; estratégia: só agregados); evangelista perde o telefone dos próprios cadastros após 30 dias; leitura de ficha por `open_person_record` registrada em `audit_log`; `income_range`, `observation`, `case_summary`, `messages` restritos a central/follow_up/unit_admin; relatórios externos com k-anonimato (≥ 5).

**Direitos e retenção:** "SAIR" → opt-out imediato; "MEUS DADOS" → `data_requests` (15 dias); `anonymize_person` apaga `people_contacts`, `children`, `messages.body`, `observation`, mantém bairro/faixa/estágio para métricas; job mensal: opt-out há 30 dias ou sem interação há 24 meses → anonimização; `messages.body` 12 meses; `wa_inbound_events.raw` 90 dias; `ai_runs.output` 90 dias; `consents`/`audit_log` 5 anos; fotos de entrega (F2) 12 meses.

**Segurança:** criptografia padrão; `phone_hash` com pepper no Vault; segredos em Supabase Secrets; `service_role` só em Edge Functions; MFA para `central`/`unit_admin`/`global_admin`; `get_advisors` + pgTAP no CI; plano de incidente (`docs/lgpd/incidentes.md`, comunicação à ANPD conforme prazo regulamentar); ROPA em `docs/lgpd/ropa.md`.

---

## 10. Roadmap

### Fase 0 — Gate (semana 0-1; bloqueia o go-live, não o início do código)
- **Gate contratual:** controlador (CNPJ, representante, DPO) definido; Business Manager do Transtornar criado, WABA, número dedicado, verificação de empresa iniciada; agência adicionada como parceira.
- **Smoke test real:** um template de teste aprovado e enviado a um telefone real antes de escrever a integração (prova que o canal existe).
- Verificação e registro da tabela de preços vigente da Meta e da Anthropic; teto mensal definido.
- Projeto Supabase `transtornar-prod` + repositório + CI + Vercel + Resend/domínio.
- Inventário da plataforma legada (vídeos, direitos, tamanho); vídeo 1 comprimido; plano B: vídeo de 60-90 s gravado pelo Breno.
- Textos: consentimento v1, política de privacidade, termo do voluntário; questionário ao cliente (§13).
- Protótipo clicável do formulário testado com 3 evangelistas no Xaxim.

### Fase 1 — MVP (semanas 1-6)
**Marco 1a (semanas 1-2) — "de pé em campo":** migrations 001-006 + seeds (Curitiba, 75 bairros com aliases, times, regras, jornada passo 0/1, templates) + RLS + pgTAP; auth por convite/senha; PWA com formulário exato, offline e "Meus cadastros"; `register_person`; `dispatch-events` com roteamento por chips; notificação à central por template interno + e-mail; `whatsapp-send`/`whatsapp-webhook` com opt-in, vídeo 1, `SAIR`. Critério: 10 cadastros reais com template entregue.
**Marco 1b (semanas 3-5):** painel `/central` mínimo (feed Realtime, fila de cesta/follow_up/central em lista, ficha com timeline, filtros, contagem por bairro + `decision_tally`, export CSV), `/admin` (convites, regras, templates, texto de consentimento), Haiku para texto livre + resumo, `merge_people`, `anonymize_person`, `data_requests`, RIPD, Playwright, piloto com 5 evangelistas no Xaxim medindo tempo de preenchimento.
**Semana 6:** ajustes do piloto, treinamento da central (modo central única, horário), go-live.
Critérios de aceite: mediana do formulário ≤ 75 s; 100% dos cadastros offline sincronizam sem duplicar; central notificada em < 30 s; ≥ 90% dos templates de opt-in entregues; opt-in ≥ 60%; zero envio a quem recusou; pgTAP verde incluindo isolamento de 2ª unidade.

**Fica de fora da Fase 1 (explícito):** série completa e `journey-tick`; feedback "o que achou"; gamificação; IA conversacional e classificação de inbound; times de itens de casa/educação/trabalho operando (regras semeadas inativas); programa de 3 meses, entregas, estoque, SLA automático, tela do entregador; UI de mesclagem de domicílios; renda e segmentação; igrejas e "integração da aba"; empresas/vagas/importação; cursos; eventos e limiares; mantenedores e benefícios; relatório institucional; Google Geocoding; Sentry; 2ª unidade/i18n; app nativo; migração de pessoas da plataforma legada; métricas por evangelista visíveis ao evangelista.

### Fase 2 — Jornada completa, times e logística (semanas 7-18)
2a (7-12): `journey-tick`, série de 8 vídeos, botões/feedback, mensagens de progresso, `reward_rules`/`reward_grants` (marcos ou pontos após decisão do cliente); Haiku para inbound + Sonnet como assistente com escalonamento; CRM de acompanhamento (`follow_ups`, conversas no painel, carteira por bairro); `assistance_programs` (3 meses, um ativo por domicílio), `delivery_orders` com fulfillment, tela do entregador, comprovante, cut-off e KPI same-day; estoque simples; `sla_policies` + escalonamento; mesclagem de domicílios; Google Geocoding; Sentry.
2b (13-18): itens de casa (catálogo, doações); educação (cursos, turmas, matrículas, instrutores se R-31a); trabalho (importação da base de empresas com staging/dedup, vagas, placements, matching Opus, revalidação a cada 30 dias); igrejas + `church_connections` + consentimento específico; renda via WhatsApp, `profile_segment`, jornadas por segmento; plano de recontato humano das pessoas da plataforma legada; descontinuação formal; `mv_impact` v1.

### Fase 3 — Eventos, empresários, mantenedores, benefícios (semanas 19-26)
`event_thresholds` com alertas 50/80/100%, eventos, convites segmentados (MARKETING, só com `marketing_events`), RSVP, check-in QR, modo evento no app; segmento empresários; funil de mantenedores com regras configuráveis, contribuições (pagamento externo por link, sem gateway próprio); clube de benefícios com carteirinha QR; relatório de impacto agregado (k ≥ 5) em PDF.

### Fase 4 — Franquia (semanas 27-32, quando houver 2ª cidade)
UI de unidades + `clone_unit_defaults`, admin global vs local, número WhatsApp por unidade, cobertura de bairros por importação IBGE, métricas comparativas, i18n de strings, playbook de onboarding, checklist LGPD por unidade.

---

## 11. Riscos e mitigações

| # | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| 1 | Controlador/CNPJ indefinido trava WABA, RIPD e termos | Média | Bloqueia go-live | Gate contratual da Fase 0; nenhum disparo real sem isso |
| 2 | Verificação da Meta / aprovação de templates atrasa | Alta | Sem WhatsApp no go-live | Smoke test na Fase 0; número de teste em dev; MVP entra com cadastro + central e fila `queued` reprocessável; plano B BSP |
| 3 | Template de opt-in reclassificado como MARKETING; quality rating cai | Média | Custo maior; limite reduzido | Texto neutro e curto, 2 variantes submetidas; throttle automático; cadência ≤ 1/dia; opt-out em 1 toque; segundo número em espera |
| 4 | Evangelistas não adotam o app | Alta | Base vazia | Protótipo testado na semana 1; login por senha com sessão de 30 dias; offline-first; instalação assistida; piloto com 5 |
| 5 | Não há times/central com gente para operar | Alta | Filas envelhecem | Modo central única; times inativos caem na central; horário declarado; digest diário ao Breno; mensagens nunca prometem prazo |
| 6 | Exposição de dado sensível | Baixa | Muito alto | PII separada, RLS testada por pgTAP, views mínimas, MFA, template neutro, anonimização automática, RIPD |
| 7 | Menor cadastrado sem responsável | Média | Violação art. 14 | Gate no formulário; jornada só ao responsável |
| 8 | Duplicidade de pessoa/domicílio | Média | Cesta dupla | `client_uuid`, dedup suave por `phone_hash`, `address_hash` + flag, um programa ativo por domicílio (F2) |
| 9 | Vídeo 1 inexistente/inadequado | Média | Sem primeiro contato útil | Inventário na Fase 0; plano B vídeo do Breno; compressão ≤ 16 MB |
| 10 | Custos de WhatsApp/IA subestimados | Média | Orçamento | Preços verificados e datados na Fase 0; `monthly_message_cap`; `cost_estimate` e `ai_runs`; relatório mensal |
| 11 | Ambiguidades da transcrição viram código | Alta | Retrabalho | F2/F3 só esboçadas; reunião de validação antes da Fase 2; `condition_type`, `member_role` flexíveis |
| 12 | Escopo cresce na Fase 1 | Alta | Perde a data | Lista "fica de fora" assinada; inclusão troca por exclusão |
| 13 | IA responde mal em tema pastoral/crise | Média (F2) | Dano | Fora do MVP; guardrails, classificador de crise, humano assume, eval com 100 casos antes de ligar |
| 14 | PWA iOS limpa IndexedDB com app sem uso por semanas | Baixa | Perda de pendências | Sync imediato ao reconectar; aviso persistente; limite de pendências |
| 15 | Bus factor (1 dev + Claude Code) | Média | Paradas | ADRs, migrations versionadas, runbooks, PRs pequenos |

---

## 12. Esforço e custo

Premissas: 1 dev sênior conduzindo o Claude Code + 0,3 PM/QA + cliente 2 h/semana. Horas humanas de condução, revisão, teste de campo e integração.

| Fase | Duração | Horas dev | Horas PM/QA | Dependências do cliente |
|---|---|---|---|---|
| 0 — Gate | 1 semana (paralela) | 20-30 | 24-32 | CNPJ/DPO, Business Manager, número, vídeo 1, lista de evangelistas |
| 1 — MVP | 6 semanas | 170-220 | 40-50 | 5 evangelistas piloto, 1-2 pessoas na central, textos aprovados |
| 2 — Jornada, times, logística | 12 semanas | 380-460 | 70-90 | Série de vídeos, marcos/pontos, voluntários entregadores, planilha de empresas, igrejas, "integração da aba" |
| 3 — Eventos, mantenedores, benefícios | 8 semanas | 220-280 | 50-60 | Modelo de benefício, parceiros, forma de contribuição |
| 4 — Franquia | 6 semanas | 120-160 | 30-40 | 2ª cidade candidata |
| **Total** | **~33 semanas** | **~910-1.150 h** | **~215-270 h** | contingência recomendada +20% |

Custos recorrentes (piloto, ~300-500 cadastros/mês): Supabase Pro US$25-45; Vercel Pro US$20; Resend US$0-20; Anthropic F1 < US$10, F2 US$40-120; Google Geocoding (F2) < US$10; **WhatsApp: variável, dominante, a calcular com a tabela vigente** (ordem de grandeza: R$1-4 por pessoa ao longo da jornada com o desenho de janela). Infra fixa ≈ US$50-90/mês na Fase 1.

---

## 13. Decisões que a agência deve confirmar

| Decisão | Recomendada | Alternativa | Quando reconsiderar |
|---|---|---|---|
| App do evangelista | PWA Next.js | Expo/React Native (push nativo, câmera intensiva, presença em loja) | Fase 3+, se um operador de franquia exigir loja; Capacitor embrulha o mesmo app |
| Provedor de WhatsApp | Meta Cloud API direta, WABA do Transtornar | BSP (360dialog/Twilio) via `WhatsAppProvider` | Se a verificação da Meta travar por mais de 3 semanas. **Z-API/Evolution: nunca** |
| Login | E-mail + senha com convite por código, sessão de 30 dias | Magic link (mais simples, pior em PWA iOS); OTP por WhatsApp/SMS (custo, F2) | Se o piloto mostrar que evangelistas não têm e-mail |
| Painel dos times | Mesmo app Next.js | Retool/Appsmith | Não recomendado (RLS e lock-in) |
| Orquestração | Outbox + `pg_cron` + Edge Functions | n8n self-hosted para campanhas ad hoc | Fase 3, só se o time quiser editar fluxos sem código |
| IA no MVP | Haiku só para texto livre (custo < US$0,002/cadastro) | MVP 100% determinístico | Se o cliente preferir adiar qualquer IA; a arquitetura não muda |
| Repositório | App único na raiz, sem monorepo | Monorepo pnpm com `packages/domain` | Fase 4, se surgir 2º app (Expo) |
| Bairro sem CEP | Select obrigatório + ViaCEP opcional | Google Geocoding no MVP | Fase 2 (logística) |
| Observabilidade | Logs Supabase/Vercel + tabelas de log | Sentry desde o MVP (free tier, +1 fornecedor) | Fase 2 |
| Dono do Business Manager | Transtornar (controlador), agência parceira | Business Manager da agência com WABA compartilhada | Não recomendado: lock-in do canal e confusão controlador/operador |
| Gamificação | `reward_rules` por marcos (7/16 dias) com `condition_type` extensível | Pontuação acumulada (`point_rules`) | Após resposta do cliente sobre "esses pontos" |

---

## 14. Perguntas bloqueantes ao cliente (fechar na Fase 0)

1. Qual pessoa jurídica é o controlador (CNPJ)? Quem é o encarregado (DPO)?
2. Existe número/WhatsApp "Transtornar"? Quem tem acesso ao Business Manager?
3. Quantos evangelistas e quem opera a central no piloto (nomes, horário)?
4. Quais times existem hoje com pessoas reais (cesta, móveis, educação, trabalho, acompanhamento)?
5. O vídeo inicial existe na plataforma legada? Quantos vídeos, formato, direitos? Há pessoas cadastradas nela (quantas)?
6. "Esses pontos": marcos em dias ou pontuação acumulada trocável por prêmios?
7. O que é "integração da aba"?
8. Evangelistas ministram os cursos do Transtornar de educação (R-31a) ou o braço já tem turmas (R-31b)?
9. Periodicidade da cesta nos 3 meses e critério de renovação; quem entrega?
10. Em que formato está a base de empresas (planilha? quantas? há CNPJ?) e quem a mantém?
11. Uso previsto para o e-mail do convertido (nenhum descrito)?
12. Aceita que a primeira mensagem seja neutra (sem mencionar Jesus) até a pessoa confirmar?