# Plano — App Transtornar (Fase 1)

Repositório `highgroundagency/brenoferreira` · branch `claude/new-session-jh3rio` · executor: Claude Code · cliente: Breno Ferreira / Transtornar · piloto: Curitiba/PR (Xaxim).

Artefatos gerados nesta sessão (copiar para `docs/` no Passo 2): requisitos consolidados (67 itens com citações e perguntas) em `/tmp/claude-0/-home-user-brenoferreira/3047d421-ed56-561a-90ae-38b027e8ebc9/scratchpad/requirements.md`; documento de arquitetura completo (SQL integral das migrations, policies, prompts) em `.../scratchpad/synthesis.md`. Este plano é o recorte executável; o SQL detalhado está na síntese.

## Contexto

Breno descreveu em áudio a visão do **Transtornar**: o evangelista cadastra na rua, em menos de um minuto, cada pessoa que aceitou Jesus (nome, e-mail, telefone, necessidade básica na casa, endereço, filhos). A central sabe na hora que "mais uma pessoa aceitou Jesus no Xaxim, o João, precisa de comida", e a demanda cai automaticamente nos times: cesta básica por 3 meses, móveis/eletrodomésticos, educação para filhos adolescentes, trabalho (empresas parceiras) ou cursos profissionalizantes. A pessoa recebe pelo WhatsApp um vídeo e depois a série "primeiros passos da vida com Deus", com botões de feedback, IA conversacional, gamificação (7 e 16 dias → Bíblia, livrinho) e conexão com uma igreja. A base por bairro/faixa etária/renda/profissão alimenta eventos por bairro, eventos para empresários, mantenedores e um clube de benefícios. Tudo deve ser **franqueável** para qualquer cidade.

Hoje existe: repositório com `README.md` e um commit. Não há projeto Supabase, página Notion nem conta WhatsApp Business do Transtornar. A agência já opera Supabase (outro cliente, `sa-east-1`); nesta organização um projeto novo custa R$ 0/mês no plano Free (confirmado via API), e o Pro entra antes do piloto.

Resultado da Fase 1 (6 semanas, Fase 0 em paralelo): PWA Next.js instalável para cadastro com fila de reenvio; Supabase multi-tenant com RLS testada em pgTAP; roteamento em SQL (estratégia, cesta básica, central); painel `/central` com feed, filas, ficha e contagem por bairro; primeiro contato pelo WhatsApp Cloud API (vídeo 1 ou opt-in, conforme o dono do número); LGPD desde o primeiro cadastro. Fases 2-4 ficam desenhadas, não aplicadas.

## Decisões assumidas

| Decisão | Recomendação | Alternativa | Por quê |
|---|---|---|---|
| App do evangelista | PWA Next.js 15 (App Router, TS), instalável; fila de reenvio simples (Dexie) | Expo/React Native; offline-first completo | Instala por link/QR sem loja; um codebase para app e painel; Xaxim é urbano com 4G |
| Painel central/admin | Mesmo projeto, route groups `(central)` e `(admin)`; gate de papel por `profiles` | Retool/Appsmith | Zero infra extra; RLS única |
| Banco/backend | Supabase novo `transtornar-prod` (`sa-east-1`, Postgres 17): Auth, RLS, Storage, Edge Functions, `pg_cron` + `pg_net`. Free no desenvolvimento, Pro antes do piloto (timebox de sessão, sem pausa por inatividade, backups) | Postgres próprio + API | Dados no Brasil; agência já opera Supabase |
| Papéis/claims | Funções `auth_unit_id()`/`auth_role()`/`auth_team_ids()` leem `profiles`/`team_members` por `auth.uid()`; **sem** Custom Access Token Hook | Claims no JWT via hook | Dezenas de usuários: uma consulta por request é irrelevante; revogação imediata; sem grants/config extras |
| Roteamento e automação | `apply_routing_rules` em plpgsql dentro da transação de `register_person`; 2 Edge Functions (`whatsapp-send`, `whatsapp-webhook`) | Outbox + webhook; n8n | Dezenas de cadastros/semana; uma lógica, um runtime, testada em pgTAP (ADR-003) |
| WhatsApp | Meta Cloud API oficial, direta, WABA/número em nome do Transtornar (agência como parceira), atrás de `WhatsAppProvider` | BSP (360dialog/Twilio) pela mesma interface | Sem risco de banimento por método; Z-API/Evolution proibidos (ADR-002) |
| Primeiro contato | `units.settings.first_contact_mode`, **dois modos implementados na F1**: `video_first` (padrão quando `phone_owner='self'`: vídeo 1 como header de template, corpo neutro) e `optin_first` (obrigatório para `family|other`: template neutro, vídeo só após "Quero receber") | Só `optin_first` | O cliente pediu "já é disparado um vídeo"; o consentimento no app é opt-in válido para a Meta; número de terceiro não recebe conteúdo sensível (ADR-002) |
| Categoria dos templates | Espelhada da Graph API; orçada como MARKETING | Assumir UTILITY | A Meta recategoriza |
| IA | Fora da F1. F2a: `claude-haiku-4-5-20251001` (classificação de inbound/texto livre, structured outputs), `claude-opus-5` (assistente e matching, thinking adaptive, effort low/medium); só em Edge Functions; ids centralizados em `_shared/models.ts` e verificados com `GET /v1/models/{id}` no primeiro deploy | IA de triagem no MVP | Roteamento por chips dispensa IA; `observation` vai à central como texto |
| Login | Convite por código → senha; e-mail + senha; `jwt_expiry` padrão + refresh; `[auth.sessions] timebox = "720h"` | Magic link; OTP WhatsApp (F2) | Magic link em PWA iOS abre fora do app |
| Bairro/CEP | Select normalizado (75 bairros, tabela global com aliases + `unaccent`/`pg_trgm`); ViaCEP opcional | Google Geocoding | Só a logística (F2) usa lat/lng |
| Multi-tenant | `units` = tenant; `unit_id NOT NULL` em toda tabela operacional; catálogos com `unit_id NULL` = padrão global (ADR-004) | Adicionar depois | Migração cara depois; cliente enfático em franquia |
| Dedup de telefone | Índice único parcial `people_contacts(unit_id, phone_e164) where is_primary`; sem hash | Hash com pepper | Hash junto do telefone em claro não reduz risco |
| Hospedagem | Vercel (`gru1`) + Supabase Cloud; Resend só como SMTP do Auth | Fly.io | Deploy por push; migrations via CI `supabase db push` |
| Notificação à central (F1) | Feed do painel com polling 30 s; título com primeiro nome para `central`/`unit_admin`, sem PII para times | Realtime; e-mail por referral | Cumpre "≤ 60 s" sem publicação Realtime |
| Observabilidade F1 | Logs Supabase/Vercel + `audit_log`, `message_log`, `referral_events`, `person_events` | Sentry | Sentry na F2 |

## Arquitetura

Componentes: (1) PWA do evangelista; (2) painel `/central` e `/admin`; (3) Postgres com RLS, triggers e RPCs `security definer` (roteamento e enfileiramento na transação); (4) `pg_cron` + `pg_net` (worker de envio a cada minuto, retenção semanal); (5) Edge Functions `whatsapp-send` e `whatsapp-webhook` (`verify_jwt = false`, validação própria); (6) Meta Cloud API; (7) Resend (SMTP do Auth); (8) Storage (bucket público `content`, vídeo 1).

```
[PWA evangelista] --falha de rede--> IndexedDB pending_registrations (client_uuid)
      | online: rpc register_person(payload)   (unit_id vem de profiles, nunca do body)
      v
[Postgres sa-east-1]  transação única, set_config('app.skip_routing','on'):
  people + people_contacts + children + needs + consents + households + person_events
  apply_routing_rules(person_id) (idempotente) -> referrals (strategy_review; basic_food; central fallback)
  notifications ; message_log(queued, scheduled_for = now()+10min dentro de 08-21h,
                              template = video1 se phone_owner='self' e modo video_first, senão optin)
      |                          pg_cron */1 -> net.http_post(edge_base_url/whatsapp-send, Bearer <vault edge_shared_secret>)
      v
[Edge whatsapp-send] valida bearer; checa consents/opt-out/quiet hours; envia template; grava wa_id da resposta
      --Graph API--> [WhatsApp da pessoa]
      ^ status sent/delivered/read/failed              | botões / texto / SAIR
[Edge whatsapp-webhook] <-- X-Hub-Signature-256 -- Meta
  raw -> wa_inbound_events (dedup_key) -> rpc handle_inbound(p_unit_id, p_wa_id, p_phone_e164, p_kind, p_payload)
  "Quero receber" -> confirm_optin -> message_log(media, vídeo 1 por link, na janela de 24 h)
  "Quero continuar"/"Assisti até o final" -> person_events(video_watched) ; "Agora não"/"Parar"/SAIR -> opt_out_person ou paused
  texto livre -> resposta fixa + referral follow_up ; template_*_update -> message_templates
      v
[Painel /central] polling 30 s: feed, filas (modo central única), ficha, contagem por bairro
```

## Modelo de dados

Convenções: `id uuid pk default gen_random_uuid()`, `created_at/updated_at timestamptz` (trigger `set_updated_at`), enums como `text + check`, **`unit_id uuid not null references units(id)` em toda tabela operacional**, identificadores em inglês. Migrations 001-007 aplicadas na F1 **só com colunas consumidas por código da F1**; F2/F3 esboçadas no apêndice. SQL completo de referência em `synthesis.md` §4 (ajustar pelas decisões desta seção).

**001 — extensões, tenancy, geografia:** `pgcrypto, unaccent, pg_trgm, pg_cron, pg_net, pgtap`. `units` (slug, name, country_code, timezone, locale, whatsapp_phone_number_id, whatsapp_waba_id, whatsapp_display_name, `whatsapp_token_secret_name text default 'WHATSAPP_ACCESS_TOKEN'`, settings jsonb: `quiet_hours`, `first_contact_delay_minutes`, `first_contact_mode ∈ video_first|optin_first`; active). `cities` (name, state, ibge_code — global). `neighborhoods` (city_id, name, normalized_name, aliases text[], region; gin trgm — global). `unit_neighborhoods`. `app_settings` (unit_id, key, value jsonb, `is_public boolean default false`): `consent_text_v1` (is_public=true), `edge_base_url` (privado, lido só por funções `security definer`).

**002 — acesso, papéis, times:** `profiles` (id = auth.users.id, unit_id nullable só para global_admin, full_name, phone_e164, role ∈ evangelist|central|team_member|unit_admin|global_admin, active, volunteer_terms_version/accepted_at, invited_by). `invites` (unit_id, email, role, team_id, code unique, expires_at, accepted_at). `teams` (unit_id, kind ∈ central|basic_food|home_items|education|employment|follow_up|logistics|strategy, name, active, fallback_to_central; unique(unit_id, kind)). `team_members` (unit_id, team_id, profile_id, member_role ∈ member|lead, active).
Funções `stable security definer set search_path = public`: `auth_unit_id()` (`select unit_id from profiles where id = auth.uid() and active`), `auth_role()`, `auth_team_ids()` (só membros ativos), `is_unit_staff()`, `can_read_unit(uuid)` = `unit_id = auth_unit_id() or auth_role() = 'global_admin'`. Perfil inativo → null → toda policy falha (revogação imediata).

**003 — pessoa, PII, domicílio, filhos, necessidades, consentimento:**
- `households` (unit_id, address_hash = sha256(normalize(street|number|complement|postal_code)), neighborhood_id, city_id, children_count; unique(unit_id, address_hash)). Criado apenas para `address_kind in ('fixed','no_number')`.
- `people` (unit_id, client_uuid unique, household_id, neighborhood_id, city_id, age_range ∈ 18_24|25_34|35_49|50_64|65_plus **nullable**, has_basic_need, children_count, needs_job, occupation_area, wants_training, attends_church, stage ∈ registered|first_contact_pending|journey_active|paused|inactive|opted_out|anonymized, stage_changed_at, decided_at, source ∈ street|event|legacy_platform|referral|import, registered_by, duplicate_of_person_id, review_status ∈ ok|possible_duplicate|merged, observation, consent_text_version, first_contact_sent_at, optin_confirmed_at, last_contact_at, anonymized_at). Índices `(unit_id, neighborhood_id, decided_at)`, `(unit_id, stage)`, `household_id`. Estágios `day7_done|day16_done|church_connected|supporter` entram na 008 (F2a).
- `people_contacts` (person_id pk, unit_id, full_name, phone_e164, **`wa_id text`** (preenchido pela resposta do primeiro envio; índice `(unit_id, wa_id)`), phone_owner ∈ self|family|other, contact_name, is_primary boolean default true, email, address_kind ∈ fixed|no_number|occupation|no_fixed_address, street, number, complement, postal_code, address_raw, whatsapp_valid). Índice único parcial `(unit_id, phone_e164) where is_primary`.
- `children` (unit_id, person_id, age_band ∈ 0_5|6_11|12_14|15_17|18_plus). `needs` (unit_id, person_id, household_id, need_type ∈ food|furniture|appliance|clothing|health|job|training|other, item_code, raw_text, detected_by ∈ evangelist|ai|team|person, status ∈ open|routed|in_assistance|fulfilled|cancelled). Trigger `needs_route` AFTER INSERT → `apply_routing_rules(person_id)`, exceto quando `current_setting('app.skip_routing', true) = 'on'`.
- `consents` (unit_id, person_id, purpose ∈ spiritual_followup|social_assistance|whatsapp_contact|marketing_events|share_with_church|share_with_employer|education_minor, granted, consent_text_version, granted_at, given_via ∈ evangelist_app|whatsapp_button|whatsapp_text|admin, collected_by, confirmed_at, confirmation_wamid, revoked_at, revoke_reason; unique(person_id, purpose, consent_text_version)). Trigger BEFORE UPDATE permite só `confirmed_at, confirmation_wamid, revoked_at, revoke_reason`.
- `decision_tally` (unit_id, neighborhood_id, registered_by, decided_on, count, minor_count). `person_events` (unit_id, person_id, event_type ∈ registered|referral_created|message_sent|optin_confirmed|video_watched|opted_out|stage_changed|contact_attempt|data_request|anonymized, actor_profile_id, payload, occurred_at) — append-only.

**004 — roteamento, filas, notificações (+ seed de `routing_rules` no fim da migration):** `routing_rules` (unit_id nullable = global, name, priority, condition jsonb, target_team_kind, referral_type ∈ basic_food|home_items|education|employment|follow_up|strategy_review|reward_delivery|church_connection|other, auto_triage, active). `referrals` (unit_id, person_id, household_id, need_id, child_id, team_id, referral_type, rule_id, reason, priority 1-3, status ∈ new|triaged|in_progress|waiting|done|cancelled, flags text[] {duplicate_household, ai_suggested}, assigned_to/at, first_response_at, done_at, outcome, cancelled_reason, parent_id; índice `(unit_id, team_id, status, created_at)`). `referral_events` append-only. `notifications` (unit_id, recipient_profile_id, team_id, kind, title, ref_table, ref_id, read_at): título com primeiro nome quando `recipient_profile_id` é central/unit_admin ("João — Xaxim — alimento"); sem PII quando destinado a `team_id`.
`apply_routing_rules(person_id)` **idempotente**: para cada regra ativa (`unit_id is null or unit_id = p.unit_id`), pula se já existe referral do mesmo `referral_type` e mesmo `need_id` (coalesce) com `status not in ('done','cancelled')`; time inativo/sem membro → `team_id` da central; `basic_food` aberto no mesmo `household_id` → flag `duplicate_household`; insere `notifications` e `person_events`.

**005 — WhatsApp (recorte F1):** `message_templates` (unit_id, name, language, category ∈ UTILITY|MARKETING|AUTHENTICATION espelhada da Graph API, meta_template_id, status ∈ pending|approved|rejected|paused, header_type, body_text, buttons, variables). `content_assets` (unit_id nullable, title, media_type ∈ video|image|document|link, public_url, duration_seconds, source ∈ new|legacy_platform, active). `message_log` (unit_id, person_id, profile_id, to_phone_e164, kind ∈ template|interactive|text|media, template_name, content_asset_id, provider, provider_message_id unique, status ∈ queued|sent|delivered|read|failed|skipped, skip_reason, error_code, error_message, payload, scheduled_for, sent_at, delivered_at, read_at; índice parcial queued). `wa_inbound_events` (unit_id, `dedup_key text unique` = sha256(wamid‖event_type‖status‖timestamp), wamid, phone_number_id, wa_id, event_type ∈ message|status|error|quality_update|template_update, raw, processed_at, error) — insert `on conflict (dedup_key) do nothing`, processa só se inseriu.

**006 — auditoria, RPCs, views, jobs:** `audit_log` append-only (unit_id, actor_id, actor_role, action, table_name, row_id, diff). RPCs `security definer`, `set search_path = public`, `revoke execute from public`; cada uma inicia com `if auth_role() not in (...) then raise insufficient_privilege` — **exceções**: `get_invite` (grant a `anon`) e `accept_invite` (grant a `authenticated`, sem exigir `profiles`); as chamadas pelas Edge Functions usam `service_role` e validam `unit_id` por `phone_number_id`.
`register_person(payload jsonb)` (idempotente por `client_uuid`: se já existe devolve `{person_id, idempotent:true}`; `set_config('app.skip_routing','on', true)`; captura `unique_violation` do índice de telefone → `is_primary=false`, `review_status='possible_duplicate'`, sem `message_log`; rejeita `is_adult=false`; escolhe o template do primeiro contato pelo modo da unidade e `phone_owner`), `record_decision_tally(neighborhood_id, minor boolean)`, `referral_transition(referral_id, to_status, note)`, `opt_out_person(p_unit_id, p_phone_e164, p_reason)`, `confirm_optin(p_unit_id, p_phone_e164, p_wamid)`, `handle_inbound(p_unit_id uuid, p_wa_id text, p_phone_e164 text, p_kind text, p_payload jsonb)` (resolve a pessoa por `wa_id`, fallback por `phone_e164` com e sem o 9º dígito: `^\+55(\d{2})9?(\d{8})$`), `open_person_record(person_id)` (grava `audit_log`), `mark_duplicate(person_id, duplicate_of)`, `confirm_distinct_person(person_id)` (central: `review_status='ok'` mantendo `is_primary=false` e `phone_owner='family'`, enfileira primeiro contato em `optin_first` endereçado a `contact_name`), `anonymize_person(person_id, reason)`, `create_invite(email, role, team_id)` → `{code, url}`, `get_invite(code)` (só email/role/expiração), `accept_invite(code)` (valida `auth.jwt()->>'email' = invites.email`, insere `profiles`), `get_my_registrations()` (`registered_by = auth.uid()`; telefone só se `created_at > now() - 30 days`; nome, bairro, estágio, status WhatsApp, selo de duplicidade), `get_team_queue(team_kind) returns setof jsonb` (`team_id = any(auth_team_ids())`; ramo `basic_food`: nome, telefone enquanto aberto, endereço + referência, bairro, `children_count`, `age_band`, needs food, flags — sem email/observation), `run_retention_policy()`, `clone_unit_defaults(new_unit_id)`. **Sem `check_phone`** (oráculo de dado sensível). Views `security_invoker` só agregadas: `v_conversions_by_neighborhood`, `v_decisions_total_by_neighborhood`, `v_impact_public` (k ≥ 5). Jobs `pg_cron`: `whatsapp-send` (`*/1`, `net.http_post` com `Authorization: Bearer` lido de `vault.decrypted_secrets where name='edge_shared_secret'`, header `x-region: sa-east-1`), `lgpd-retention` (semanal).

**007 — dados de referência (idempotente, `on conflict do nothing`):** unidade `curitiba`, Curitiba/PR (IBGE 4106902), 75 bairros com aliases (Xaxim: `{chaxim,chachim}`), cobertura, times (central, basic_food, follow_up, strategy ativos), `app_settings` (`consent_text_v1` público). `supabase/seed.sql` só com dados locais (usuários de teste, unidade `teste`, `edge_base_url` local, `select vault.create_secret('dev-edge-secret', 'edge_shared_secret', 'bearer das Edge Functions')`). `supabase/seeds/prod.sql` **sem segredos**: `edge_base_url` real, `message_templates` espelhado da Graph API, `content_assets` do vídeo 1; o segredo de produção é criado pelo CI a partir de variável (Passo 11).

**RLS por papel:** RLS em todas as tabelas; SELECT com `can_read_unit(unit_id)`; catálogos (`routing_rules`, `message_templates`, `content_assets`) com leitura `unit_id is null or unit_id = auth_unit_id()`; `app_settings` com leitura `can_read_unit(unit_id) and is_public`. `global_admin`: SELECT em tudo (auditado); INSERT/UPDATE/DELETE apenas em `units`, `cities`, `neighborhoods`, `unit_neighborhoods`, `profiles` e nas linhas `unit_id is null` dos catálogos; nenhuma escrita em tabelas operacionais.

| Tabela | evangelist | team_member | central / unit_admin | global_admin |
|---|---|---|---|---|
| `people`, `people_contacts`, `children`, `needs`, `consents`, `households` | sem SELECT; insert via RPC; leitura por `get_my_registrations()` | sem policy; leitura por `get_team_queue()` | select/update da unidade | leitura |
| `referrals`, `referral_events` | nenhum | select `team_id = any(auth_team_ids())`; transição via RPC | tudo da unidade | leitura |
| `message_log`, `wa_inbound_events`, `audit_log` | nenhum | nenhum | leitura | leitura |
| `notifications` | próprias | próprias + do time | tudo | leitura |
| `profiles` | própria linha | própria | leitura da unidade; unit_admin edita | escrita |
| `units`, `cities`, `neighborhoods`, `unit_neighborhoods`, catálogos, `app_settings` públicos | leitura | leitura | leitura; unit_admin edita os da própria unidade | escrita (ver recorte acima) |

pgTAP obrigatório (8 arquivos): `isolation_second_unit.sql` (inclui catálogo global vs local), `rls_evangelist.sql` (não lê outros; perde telefone após 30 d; lê `consent_text_v1`; `referral_transition` → erro; RPC sem grant → erro), `rls_team_member.sql` (só `get_team_queue`, sem observation; perfil inativado → zero linhas), `rls_global_admin_readonly.sql` (recorte exato de escrita), `register_person.sql` (transação, idempotência 2× mesmo payload, dedup, household, tally, menor rejeitado, escolha do template por modo/`phone_owner`), `routing.sql` (2 necessidades → exatamente 1 `strategy_review`; time inativo → central; mesmo household → flag), `anonymize_person.sql` (telefone ausente em todas as tabelas), `retention.sql` (inclui `ok(count(vault.decrypted_secrets where name='edge_shared_secret') = 1)`).

## Formulário do evangelista

Uma tela obrigatória (~45-60 s) + seção recolhida "Mais detalhes" (~20 s). Chips e toggles em vez de digitação; botão fixo "Registrar decisão". Meta: mediana ≤ 75 s. Protótipo clicável testado com 3 evangelistas e lista de campos aprovada por Breno na Fase 0.

| # | Campo | Coluna | UI | Obrig. |
|---|---|---|---|---|
| 1 | Nome | `full_name` | texto (aceita só primeiro nome) | Sim |
| 2 | WhatsApp | `phone_e164` | máscara `(41) 9 9999-9999`; read-back do número na tela de confirmação; botão de contatos só se `'contacts' in navigator && 'ContactsManager' in window` | Sim |
| 2a | O número é… | `phone_owner`, `contact_name` | chips: própria pessoa · família · outro (+ nome de quem atende) | Sim (default própria) |
| 3 | Idade | gate `is_adult` + `age_range` | uma linha de chips: Menor de 18 · 18-24 · 25-34 · 35-49 · 50-64 · 65+ · Prefiro não dizer. "Menor de 18" desabilita "Registrar decisão" e deixa só o tally (`minor=true`); "Prefiro não dizer" grava `age_range=null`, `is_adult=true` | Sim (um toque) |
| 4 | Bairro | `neighborhood_id` | select com busca, último usado como padrão; CEP opcional via ViaCEP | Sim |
| 5 | Endereço | `address_kind`, `street`, `number`, `complement`, `postal_code`, `address_raw` | chips: casa com número · sem número/fundos · ocupação · sem endereço fixo; campos conforme o tipo | Sim (referência quando não há número) |
| 6 | Precisa de algo em casa? | `has_basic_need`, `needs` | chips multi: Alimento · Móvel · Eletrodoméstico · Roupas · Saúde · Nada; sub-chips cama/sofá/fogão/geladeira/máquina | Sim (pode ser "Nada") |
| 7 | Filhos | `children_count`, `children.age_band` | stepper 0-9; por filho chip de faixa | Sim (default 0) |
| 8 | Consentimento | `consents` + `consent_text_version` | roteiro lido em voz alta + 1 checkbox + link do termo; desmarcado desabilita "Registrar decisão" | Sim |
| — | **Mais detalhes (recolhido)** | | | |
| 9 | Trabalho | `needs_job`, `wants_training`, `occupation_area` | toggles + chips de área (cozinha, construção, limpeza, vendas, transporte, cuidados, administrativo, autônomo/empresário, outro) | Não |
| 10 | Já frequenta igreja? | `attends_church` | Sim / Não / Não sei | Não |
| 11 | Algo que a central deve saber? | `observation` + `needs.raw_text` | texto ≤ 140 caracteres | Não |
| 12 | E-mail | `email` | e-mail | Não |
| 13 | Aceitou em outra data? | `decided_at` | toggle + data | Não |

Roteiro de consentimento v1: "O Transtornar vai guardar seu nome, telefone, endereço e sua decisão por Jesus para te acompanhar. Vamos falar com você pelo WhatsApp. Você pode pedir para parar ou apagar seus dados a qualquer momento respondendo SAIR ou MEUS DADOS." + (só com necessidade marcada) "Seus dados também vão para a equipe que cuida de cesta básica e itens de casa." Grava `spiritual_followup` + `whatsapp_contact` sempre; `social_assistance` só com necessidade; demais finalidades só por botão no WhatsApp.

Além dos campos citados pelo cliente entram, um toque cada: dono do número (define o modo do primeiro contato), idade (gate de maioridade, art. 14 LGPD), tipo de endereço (ocupação/sem número), faixa por filho (educação usa idade), consentimento (art. 11 + opt-in Meta). Automáticos: `unit_id`, `registered_by`, `decided_at`, `source`, `client_uuid`, `consent_text_version`, `city_id`, `household_id`. Não coletados: renda (F2 via WhatsApp), GPS, CPF, data de nascimento, nome/gênero dos filhos, foto.

Recusa de dados / menor: botão "Aceitou Jesus mas não será cadastrado(a)" → `record_decision_tally`. Tela de sucesso: "João registrado no Xaxim. Vídeo de boas-vindas agendado." (fila: "Salvo no aparelho — envia quando houver sinal"); nunca promete entrega ou prazo.

## Roteamento e times

Motor: `apply_routing_rules(person_id)` plpgsql, idempotente, chamado por `register_person` (com `app.skip_routing` durante os inserts) e pelo trigger `needs_route` (central registra nova necessidade); testado em `routing.sql`. `condition`: `{"always":true}`, `{"need_type":"food"}`, `{"need_type_in":[...]}`, `{"children_age_band_in":[...]}`, `{"needs_job":true}`.

| Prioridade | Condição | Time | Tipo | auto_triage | Ativa no MVP |
|---|---|---|---|---|---|
| 5 | sempre | strategy | strategy_review | true | Sim |
| 10 | `need_type = food` | basic_food | basic_food | true | Sim |
| 20 | `need_type in (furniture, appliance)` | home_items | home_items | false | Não (cai na central) |
| 30 | `children.age_band in (12_14, 15_17)` | education | education | false | Não |
| 40 | `needs_job or wants_training` | employment | employment | false | Não |
| 50 | texto livre inbound (F1) / `ai_intent in (help, crisis, prayer)` (F2) | follow_up | follow_up | true | Sim |

Regras fixas: time `active=false` ou sem membro ativo → central (`fallback_to_central`); `basic_food` aberto no mesmo `household_id` → flag `duplicate_household` (central decide, sem cesta dupla); pessoas sem household → checagem só por telefone. **Modo central única** no MVP: uma pessoa vê todas as filas numa tela; `strategy_review` aparece na fila unificada e fecha com `referral_transition(done)`. Notificação = feed do painel (polling 30 s); e-mail/WhatsApp interno para times na F2a.

IA: fora da F1. `observation`/`raw_text` aparecem na ficha; a central cria/ajusta `needs` à mão. F2a: Haiku classifica texto livre e inbound (structured outputs via `output_config.format`, entrada pseudonimizada, `ai_runs`, teto diário), fallback determinístico; detalhes em `docs/adr/005-ai.md` após as perguntas 5 e 6.

Estados de `referrals`: `new → triaged → in_progress → waiting → done`, `cancelled` de qualquer estado; reatribuição = novo referral com `parent_id` + original `cancelled(reassigned)`. Só via `referral_transition()` (valida transição e `auth_team_ids()`, grava `referral_events`, `first_response_at`, `done_at`). SLA automático na F2; no MVP o painel mostra "sem responsável há X h".

## Jornada WhatsApp

Regras de envio (`whatsapp-send`): nada sai sem `consents(whatsapp_contact, granted, revoked_at is null)`; `SAIR|PARAR|CANCELAR` ou botão "Parar"/"Agora não" → `opt_out_person`/`paused` em < 1 min, confirmação única; quiet hours 21h-08h (por unidade), fora disso agenda 08h; janela de 24 h aberta por qualquer resposta permite mídia/texto grátis; erro `131026` (sem WhatsApp) → `whatsapp_valid=false` + selo em "Meus cadastros" + referral `follow_up` (motivo `no_whatsapp`); vídeo 1 por `link` (bucket público, ≤ 16 MB) — sem upload de mídia nem `wa_media_id` na F1; a resposta do envio grava `people_contacts.wa_id`. Categoria/status dos templates vêm de `GET /{waba_id}/message_templates` e dos webhooks `message_template_status_update`/`template_category_update`. Token por unidade: `Deno.env.get(unit.whatsapp_token_secret_name)`.

| Passo | Quando | Modo | Conteúdo | Template | Botões | Fase |
|---|---|---|---|---|---|---|
| 0-V | T+10 min (08-21h) após cadastro | `video_first` (`phone_owner='self'`) | header: vídeo 1 por link; corpo: "Olá {{1}}! Aqui é o Transtornar. Preparamos este vídeo para você. Para parar a qualquer momento, responda SAIR." | `transtornar_video1_v1` | Quero continuar / Parar | 1 |
| 0-O | T+10 min (08-21h) após cadastro | `optin_first` (`family|other`, ou unidade configurada assim) | "Olá {{1}}! Aqui é o Transtornar. Registramos seu contato hoje. Quer receber nossas mensagens e vídeos? Para parar, responda SAIR." | `transtornar_optin_v1` | Quero receber / Agora não | 1 |
| 0b | +48 h sem resposta | ambos | lembrete único, mesmo texto curto | `transtornar_lembrete_v1` | idem | 1 |
| 1 | após "Quero receber" (só `optin_first`) | — | vídeo 1 como mídia por link, dentro da janela | — | Assisti até o final | 1 |

Cliques: "Quero receber"/"Quero continuar" → `confirm_optin` (`consents.confirmed_at`, `stage='journey_active'`) (+ vídeo 1 no modo opt-in); "Assisti até o final"/"Quero continuar" → `person_events(video_watched, {content_asset_id})` visível na ficha (feedback "o que achou" só na F2a); "Agora não" → `stage='paused'`; "Parar"/SAIR → `opt_out_person`; sem resposta após lembrete + 14 dias → `stage='inactive'` + referral `follow_up` para contato humano (nunca anonimização por silêncio).

F2a: série de N vídeos por `day_offset` com botões de confirmação e feedback, mensagens de progresso, `journey-tick` (`pg_cron` 15 min), `reward_rules.condition_type ∈ step_completed|milestone_days|points_threshold`, assistente IA com classificação de intenção e escalonamento humano em ≤ 1 h — detalhar em ADR após as perguntas 5 e 6.

## Fase 0 — pré-requisitos (semana 0-1, em paralelo aos Passos 1-8; dono: cliente + agência)

Gate dos Passos 9, 11 e do piloto. Pronto quando:
- (a) CNPJ do controlador e DPO nomeados; textos v1 de consentimento, política de privacidade e termo do voluntário aprovados.
- (b) Meta Business Portfolio do Transtornar criado, Business Verification iniciada, app WhatsApp + WABA criados, número dedicado registrado (nunca usado em WhatsApp comum), display name aprovado, agência adicionada como parceira; app inscrita na WABA (`POST /{waba_id}/subscribed_apps`); `WHATSAPP_ACCESS_TOKEN` = token permanente de System User; smoke test: template de teste entregue a um telefone real.
- (c) Templates `transtornar_video1_v1`, `transtornar_optin_v1` e `transtornar_lembrete_v1` submetidos; categoria/status espelhados em `message_templates` (`seeds/prod.sql`); preços vigentes da Meta em `docs/ops/whatsapp-pricing.md` (data, modelo por mensagem).
- (d) Inventário da plataforma legada em `docs/content/inventario.md`; vídeo 1 comprimido (≤ 16 MB, H.264/AAC), direitos confirmados, publicado no bucket `content`; plano B: vídeo de 60-90 s gravado pelo Breno.
- (e) Respostas às perguntas 4, 5, 12, 13, 14 e 15 (lista de campos do formulário aprovada por Breno, com os cinco campos adicionados e a justificativa de um toque cada); lista de 5 evangelistas e de quem opera a central.
- (f) Protótipo clicável do formulário testado com 3 evangelistas no Xaxim.

## Fase 1 (MVP) — passos de implementação

Fase 1a (semanas 1-4, sem dependência externa): Passos 1-8. Fase 1b (semanas 5-6, ou quando a WABA for aprovada): Passos 9-11. Commits pequenos por passo; PR por marco; `supabase db diff` no PR; sem segredos no repo.

**Passo 1 — Scaffold** (`create-next-app` recusa diretório com `README.md`; gerar em pasta temporária e copiar):
```
pnpm dlx create-next-app@15 transtornar-tmp --ts --tailwind --app --no-src-dir --import-alias "@/*" --use-pnpm --no-eslint --no-turbopack
mv README.md README.original.md && rsync -a transtornar-tmp/ ./ && rm -rf transtornar-tmp
# mesclar README.original.md no README.md gerado e remover o .original
pnpm add -D @biomejs/biome vitest @vitest/coverage-v8 @playwright/test && pnpm biome init
pnpm dlx shadcn@latest init -d -y && pnpm dlx shadcn@latest add -y button input form select checkbox toggle badge card sheet table sonner
pnpm add @supabase/supabase-js @supabase/ssr react-hook-form zod @hookform/resolvers libphonenumber-js dexie @serwist/next serwist @tanstack/react-table
```
`messages/pt-BR.json` + helper `lib/i18n.ts` (`t(key)`, ~10 linhas; `next-intl` só na F4); `app/manifest.ts`; `app/sw.ts` (app shell); `next.config.ts` com `withSerwist({ swSrc: 'app/sw.ts', swDest: 'public/sw.js', disable: process.env.NODE_ENV === 'development' })`; README documenta que `dev`/`build` rodam com webpack (Serwist não suporta Turbopack) e HTTPS local via `next dev --experimental-https` ou `cloudflared tunnel --url http://localhost:3000` (o mesmo túnel serve o webhook da Meta). Pronto quando: `pnpm build` verde; PWA instalável na preview HTTPS da Vercel (Chrome Android e Safari iOS).

**Passo 2 — Supabase local + estrutura + docs.** `supabase init`; `supabase start`; `supabase migration new 001_extensions_tenancy_geo` … `007_reference_data`; `supabase functions new whatsapp-send`, `whatsapp-webhook`. `config.toml`:
```
[auth.email]
enable_signup = true
enable_confirmations = false
[auth.sessions]
timebox = "720h"
[functions.whatsapp-send]
verify_jwt = false
[functions.whatsapp-webhook]
verify_jwt = false
```
Copiar `requirements.md` → `docs/requisitos.md` e `synthesis.md` → `docs/arquitetura.md`. Árvore alvo:
```
middleware.ts                       (só exige sessão; matcher exclui _next/static, sw.js, manifest.webmanifest)
app/
  (campo)/nova-pessoa/page.tsx  (campo)/meus-cadastros/page.tsx  (campo)/layout.tsx   (layout lê profiles.role e redireciona)
  (central)/central/page.tsx  (central)/central/filas/[teamKind]/page.tsx  (central)/central/pessoas/[id]/page.tsx  (central)/central/bairros/page.tsx
  (admin)/admin/usuarios/page.tsx
  (auth)/login/page.tsx  (auth)/convite/[code]/page.tsx  api/auth/callback/route.ts  api/cep/[cep]/route.ts
components/ (form/, central/, ui/)
lib/supabase/{client.ts,server.ts,middleware.ts}  lib/database.types.ts  lib/i18n.ts
lib/domain/{phone.ts,address.ts,referral-state.ts,schemas.ts}   lib/offline/{db.ts,queue.ts}
lib/whatsapp/{provider.ts,meta-cloud.ts}
supabase/migrations/001..007.sql  supabase/seed.sql  supabase/seeds/prod.sql  supabase/config.toml
supabase/functions/_shared/{supabase.ts,models.ts,auth.ts}  supabase/functions/{whatsapp-send,whatsapp-webhook}/index.ts
supabase/tests/{isolation_second_unit,rls_evangelist,rls_team_member,rls_global_admin_readonly,register_person,routing,anonymize_person,retention}.sql
tests/unit/  tests/e2e/  docs/adr/  docs/lgpd/  docs/ops/  docs/content/  .github/workflows/ci.yml
```
Pronto quando: `supabase db reset` aplica migrations vazias; `pnpm dev` conecta ao Supabase local.

**Passo 3 — Migrations 001-002 + 007 (parcial) + seed local.** Escrever 001, 002 (funções `auth_*` lendo `profiles`) e 007 apenas com `units`, `cities`, `neighborhoods`, `unit_neighborhoods`, `app_settings`, `teams` (o seed de `routing_rules` fica no fim da 004). `seed.sql`: unidade `teste` (só local/CI), usuários `evangelist@test`, `central@test`, `basic_food@test`, `unit_admin@test`, `global_admin@test`, `app_settings(edge_base_url)` = `http://supabase_kong_<project_id>:8000/functions/v1` (de `supabase status`; documentado em `docs/ops/runbook.md`), `select vault.create_secret('dev-edge-secret', 'edge_shared_secret', 'bearer das Edge Functions')` com o mesmo valor em `supabase/.env.local` (`EDGE_SHARED_SECRET`). Pronto quando: `db reset` popula 75 bairros; `select auth_role()` como `evangelist@test` devolve `evangelist`; inativar o perfil devolve null.

**Passo 4 — Migrations 003-004 + roteamento em SQL.** Tabelas de pessoa/PII/domicílio/filhos/necessidades/consentimentos/tally/timeline; `routing_rules` (+ seed no fim da 004), `referrals`, `referral_events`, `notifications`, `apply_routing_rules` idempotente, trigger `needs_route` com `app.skip_routing`. Pronto quando: `routing.sql` provisório (inserts diretos em `people`/`needs` + `apply_routing_rules(person_id)`) prova: alimento + 2 necessidades gera exatamente 1 `strategy_review` + 1 `basic_food`; time inativo cai na central; mesmo household → `duplicate_household`; novo `needs` → 1 referral novo.

**Passo 5 — Migrations 005-006 + RLS + pgTAP.** `message_templates`, `content_assets`, `message_log`, `wa_inbound_events` (`dedup_key`), `audit_log`; todas as RPCs (incl. `register_person` idempotente com household na transação, `is_primary`, rejeição de menor, escolha do template por modo/`phone_owner`; `confirm_distinct_person`; `get_team_queue` como `setof jsonb`; `anonymize_person` completa); grants (`get_invite` → `anon`, `accept_invite` → `authenticated`, demais `revoke from public`); views; `cron.schedule` com URL de `app_settings.edge_base_url`, bearer do Vault e `x-region: sa-east-1`; `enable row level security` em todas + policies com `can_read_unit`/`is_public`. Pronto quando: `supabase test db` verde nos 8 arquivos (o cenário via `register_person` passa a valer aqui); `supabase db lint` limpo; `supabase gen types typescript --local > lib/database.types.ts`.

**Passo 6 — Auth por convite e senha.** `/admin/usuarios` chama `create_invite` e exibe o link `NEXT_PUBLIC_APP_URL/convite/<code>` com botão "copiar" (o admin envia por WhatsApp; e-mail automático na F2a); `/convite/[code]` chama `get_invite`, faz `signUp({email, password})`, chama `accept_invite(code)` e redireciona; `/login`; `middleware.ts` só verifica sessão (`getUser`); cada route group lê `profiles.role` no layout server-side e redireciona quem não pertence. Resend em `[auth.email.smtp]` para redefinição de senha. Pronto quando: convite → senha → login → `/nova-pessoa` em PWA instalado no iOS sem sair do app; `basic_food@test` em `/central` é redirecionado (Playwright local `role-gate.spec.ts`).

**Passo 7 — Formulário "Nova pessoa" + fila de reenvio.** `schemas.ts` (zod exato da §Formulário: chips de idade com gate, consentimento), `phone.ts` (E.164 + variante sem 9º dígito), `address.ts` (`address_hash` só para fixed/no_number, com complemento), chips/stepper, select de bairro, `api/cep/[cep]` (ViaCEP → BrasilAPI), consentimento com texto de `app_settings` (`is_public`), read-back do telefone na confirmação, botão de contatos com feature-detect. Fila: ao falhar o POST, gravar em `pending_registrations` (Dexie, por `client_uuid`) e reenviar no evento `online`/abertura do app. "Meus cadastros" via `get_my_registrations()`. Pronto quando: Vitest (`phone`, `address`, `schemas`, `referral-state`) verde; `pnpm e2e` (`register-online.spec.ts`) verde local; reenvio 2× do mesmo `client_uuid` gera 1 linha em cada tabela (pgTAP); teste manual de fila em `docs/ops/teste-offline.md`.

**Passo 8 — Painel `/central` mínimo.** Feed com polling 30 s (`router.refresh()`/SWR), filas por time em modo central única (inclui `strategy_review` e `follow_up`), ficha via `open_person_record` (timeline + referrals + status WhatsApp + `observation`), `referral_transition`, `mark_duplicate`, `confirm_distinct_person` ("Mesma casa, pessoa diferente"), `anonymize_person`, registro de pedido LGPD em `person_events(data_request)`, contagem por bairro (`v_conversions_by_neighborhood` + `v_decisions_total_by_neighborhood`). Pronto quando: usuário `central` vê cadastro novo em ≤ 60 s sem recarregar; `team_member` de basic_food só vê `get_team_queue('basic_food')`. **Fim da Fase 1a.**

**Passo 9 — `WhatsAppProvider` + `whatsapp-send` + `whatsapp-webhook`** (gate: Fase 0 b-d). `provider.ts` (`sendTemplate`, `sendMedia`, `sendInteractive`, `listTemplates`, `verifyWebhook`), `meta-cloud.ts` (versão em `WHATSAPP_API_VERSION`, token por `unit.whatsapp_token_secret_name`). `whatsapp-send`: compara o bearer com `EDGE_SHARED_SECRET` (401 caso contrário); lê `message_log queued` com `scheduled_for <= now()`, checa consentimento/opt-out/quiet hours, escolhe template (`video1`/`optin`/`lembrete`) ou mídia por link, grava `provider_message_id` e `people_contacts.wa_id` (de `contacts[0].wa_id`). `whatsapp-webhook`: GET de verificação (`hub.verify_token`), POST valida `X-Hub-Signature-256` (HMAC-SHA256 do body bruto com `WHATSAPP_APP_SECRET`), resolve `unit_id` por `phone_number_id`, insere `wa_inbound_events` por `dedup_key`, statuses → `message_log`, botões/texto → `handle_inbound(p_unit_id, p_wa_id, '+'||wa_id, kind, payload)` (resolução por `wa_id`, fallback com/sem 9º dígito), `template_*_update` → `message_templates`; deploy com `--no-verify-jwt`. Pronto quando: requisição sem bearer/assinatura → 401; em número de teste, template entregue nos dois modos; "Quero continuar"/"Quero receber" → `journey_active` (+ vídeo 1 no modo opt-in); "Assisti" → `person_events`; `SAIR` → próximos envios `skipped`; `wa_id` de 12 dígitos casa com E.164 de 13 (teste Deno); `sent/delivered/read` do mesmo wamid refletidos em `message_log`; `docs/ops/whatsapp.md` cobre `functions serve` + túnel.

**Passo 10 — Retenção e hardening.** `run_retention_policy()` (F1: silêncio após lembrete + 14 d → `inactive` + referral `follow_up` + `person_events(contact_attempt)`; opt-out há 30 d → `anonymize_person('opted_out')`), `get_advisors` sem alertas de segurança, `docs/lgpd/{ripd,operadores,retencao}.md` (RIPD registra minimização por estágio, não por exclusão), `docs/adr/{001-pwa,002-whatsapp-cloud-api,003-routing-in-db,004-multitenant}.md`, `docs/ops/runbook.md` (`net._http_response` para depurar cron). Pronto quando: `retention.sql` prova `inactive` + referral no caso de silêncio e anonimização no caso de opt-out; `anonymize_person.sql` verde.

**Passo 11 — CI, deploy e piloto.** `ci.yml`: `biome check`, `vitest run`, `supabase start` + `db lint` + `test db`, `deno test supabase/functions` (`denoland/setup-deno`); deploy na `main`: `supabase link`, `db push`, `supabase config push` (confirmação de e-mail desligada, SMTP Resend, timebox), `psql "$DATABASE_URL" -f supabase/seeds/prod.sql` (primeira vez), criação única do segredo `psql "$DATABASE_URL" -v secret="$EDGE_SHARED_SECRET" -c "select vault.create_secret(:'secret','edge_shared_secret') where not exists (select 1 from vault.secrets where name='edge_shared_secret')"`, `supabase secrets set`, `functions deploy whatsapp-send whatsapp-webhook --no-verify-jwt`, Vercel (`gru1`); `DATABASE_URL` montada de `SUPABASE_PROJECT_REF` + `SUPABASE_DB_PASSWORD` (pooler `sa-east-1`, porta 5432); projeto `transtornar-prod` criado como Free e promovido a Pro antes do piloto; JWT assimétrico. Playwright fica em `pnpm e2e` local antes do PR de marco. Pronto quando: pipeline verde; `select count(*) from neighborhoods` = 75 em produção; app da Meta em Live, templates aprovados, teste com 3 números reais fora da lista de teste; piloto com 5 evangelistas no Xaxim.

Variáveis (nomes apenas). Vercel: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_APP_URL`. Supabase Secrets (Edge): `EDGE_SHARED_SECRET`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_API_VERSION`. Vault: `edge_shared_secret`. Auth SMTP: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`. CI: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `EDGE_SHARED_SECRET`, `VERCEL_TOKEN`. F2: `ANTHROPIC_API_KEY`.

Critérios de aceite. F1a: mediana do formulário ≤ 75 s; cadastros no painel em ≤ 60 s sem recarregar; zero cadastros perdidos entre aparelho e banco; pgTAP verde com isolamento de 2ª unidade. F1b: primeiro contato entregue em ≥ 90% dos cadastros com `whatsapp_valid`; `SAIR` bloqueia; zero mensagens a quem não tem `consents.whatsapp_contact`; taxa de resposta registrada só como observação.

Fica de fora da Fase 1: fluxo de menor com responsável; série completa e `journey-tick`; feedback "o que achou"; gamificação; qualquer IA; times de itens de casa/educação/trabalho operando; programa de 3 meses, entregas, estoque, SLA automático; `merge_people`; export CSV; e-mail/WhatsApp interno para staff; Realtime; telas de regras/templates/consentimento/conteúdo em `/admin`; MFA; renda e segmentação; igrejas; empresas/vagas; cursos; eventos; mantenedores; relatório institucional; Geocoding; Sentry; offline-first completo; i18n; app nativo; migração da plataforma legada; métricas por evangelista visíveis ao evangelista; `check_phone`.

## Fases 2, 3 e visão

Ordem após a F1: 2a → 2b → 3 → 4; sem semanas até as perguntas 4-10 serem respondidas.

**Fase 2a — jornada completa, acompanhamento e logística:** migrations 008+ (`person_journeys`, `journey_steps`, `journey_progress`, `conversations`, `messages`, `ai_runs`, `data_requests`, `follow_ups`, `reward_rules`/`reward_grants`, `assistance_programs`, `delivery_orders`, `sla_policies`; colunas `income_range`, `profile_segment`, `case_summary`, `adults_count`, `merged_into_id`, `pricing_category`, `cost_estimate`, `monthly_message_cap`, `same_day_cutoff`, `member_role instructor|driver`); série de vídeos com `journey-tick`; fluxo de menor com responsável presente (`given_by='guardian'`); Haiku para inbound + Opus 5 como assistente (eval de 100 casos antes de ligar); CRM no painel; Realtime; e-mail de convite e notificações a times (Resend via `pg_net`, sem PII); programa de 3 meses (um ativo por domicílio), fulfillment, tela do entregador, comprovante, KPI same-day; notificação de status de entrega via template `transtornar_entrega_v1` à pessoa com `consents.social_assistance` e selo em "Meus cadastros"; `/central/bairros` com filtros por período, estágio e cidade; retenção completa (abaixo); `/admin` completo; `merge_people`; export CSV; MFA; Geocoding; Sentry; ROPA e plano de incidentes.
**Fase 2b — times e integrações:** itens de casa; educação (`courses`, `course_classes`, `enrollments`, instrutores se R-31a); trabalho (`companies` com `roles[]`, `job_openings`, `job_placements`, importação com staging/dedup por CNPJ ou telefone, matching Opus 5 em batch); `churches` + `church_connections`; renda via WhatsApp, `profile_segment`, jornadas por segmento; recontato humano das pessoas da plataforma legada; decisão formal de descontinuação da plataforma legada (data, comunicação, destino dos vídeos, exportação final); `mv_impact` v1.
**Fase 3:** `event_thresholds` (alertas 50/80/100%), `events` com `target_segment jsonb`, `event_invitations` por filtro configurável (bairro, faixa etária, renda, segmento, estágio), convites MARKETING só com `marketing_events`, RSVP, check-in QR, modo evento; segmento empresários; `supporters` + `supporter_eligibility_rules` + `contributions` (pagamento por link externo); métricas de mantenedores por faixa/renda/origem; `benefits`/`benefit_redemptions`; relatório de impacto (k ≥ 5) em PDF.
**Fase 4 / visão:** UI de unidades + `clone_unit_defaults`, admin global vs local, número por unidade, importação IBGE de bairros, métricas comparativas, `next-intl`, playbook e checklist LGPD por unidade.

Apêndice — esboço F2/F3 (não aplicar; validar com o cliente): `assistance_programs` (household_id, program_type, start/end, planned/completed_deliveries, status; unique ativo por domicílio), `delivery_orders` (status scheduled→delivered|failed, address_snapshot, proof_photo_path), `catalog_items`/`inventory_stock`, `churches`/`church_connections`, `courses`/`course_classes`/`enrollments`/`volunteer_availability`, `companies`/`company_contacts`/`job_openings`/`job_placements`/`import_batches`, `reward_rules` (condition_type)/`point_rules`/`points_ledger`/`reward_grants`, `events` (target_segment jsonb)/`event_thresholds`/`event_invitations`, `supporters`/`supporter_eligibility_rules`/`contributions`/`benefits`/`benefit_redemptions`.

## LGPD e segurança

- **Natureza e base legal:** existir em `people` = dado sensível (convicção religiosa, art. 5º, II); base legal = consentimento específico e destacado (art. 11, I). Finalidades em `consents.purpose`; `social_assistance` só com necessidade declarada; igreja/empresa/eventos só por botão no WhatsApp. Contatos de empresas (F2): legítimo interesse B2B com `company_contacts.legal_basis`.
- **Consentimento:** roteiro lido em voz alta + checkbox + `consent_text_version`, `collected_by`, `client_uuid`; é opt-in válido para a Meta. Confirmação pelo botão no WhatsApp (`confirmed_at`, `confirmation_wamid`) é o gate da série automática de vídeos (F2a), **não** da existência do cadastro. Conteúdo com teor religioso (vídeo 1) só vai ao número da própria pessoa (`phone_owner='self'`); número de terceiro recebe template neutro. Sem checkbox o app grava só `decision_tally`.
- **Menores:** F1 cadastra só maiores de 18; menores contam no tally (`minor_count`), sem nome/telefone. Filhos só por faixa etária. Fluxo de responsável presente e `education_minor` na F2.
- **Papéis:** controlador = PJ do Transtornar (CNPJ e DPO na Fase 0); operadora = High Ground; sub-operadores: Supabase, Vercel, Meta, Resend (Anthropic, Google, Sentry na F2). Banco e Edge Functions em `sa-east-1`; Meta com minimização e registro de transferência internacional (art. 33). RIPD e registro de operadores em `docs/lgpd/` na F1.
- **Minimização por papel:** PII em `people_contacts`; evangelista e times leem só por RPCs com colunas restritas; evangelista perde o telefone após 30 dias; sem `check_phone`; leitura de ficha via `open_person_record` → `audit_log`; `observation` só central/unit_admin; `notifications` sem PII para times; estratégia sem contato; relatórios externos com k ≥ 5.
- **Direitos e retenção** (`run_retention_policy`, semanal): `SAIR` → opt-out imediato; `MEUS DADOS` → `person_events(data_request)` com prazo de 15 dias; silêncio após lembrete + 14 dias → `stage='inactive'` + referral `follow_up` (contato humano), **nunca anonimização por silêncio**; opt-out há 30 dias → anonimização (F1). F2a: "Agora não" + 90 dias sem interação → `inactive` + referral `follow_up`; `131026` (sem WhatsApp) → referral `follow_up` imediato com motivo `no_whatsapp`, sem prazo de anonimização; anonimização automática apenas por opt-out (30 d), pedido do titular, ou 24 meses sem qualquer interação **e** sem `assistance_programs`/`referrals`/`enrollments`/`job_placements` ativos; `wa_inbound_events.raw` 90 dias; `consents`/`audit_log` 5 anos (diff anonimizado).
- **`anonymize_person` limpa:** delete `people_contacts` e `children`; `people.observation` = null; `needs.raw_text` = null; `referrals.reason` = tipo genérico; `notifications.title` = "Pessoa anonimizada"; `person_events.payload` = `{}`; `message_log.to_phone_e164` = null e `payload` = `jsonb_build_object('template', template_name)`; `audit_log.diff` = null nas linhas da pessoa; `stage='anonymized'`, mantém bairro/faixa/estágio anterior para métricas. Provado por `anonymize_person.sql`.
- **Segurança:** segredos em Supabase Secrets e Vault (nunca em `seeds/prod.sql` nem no repo); `service_role` só em Edge Functions; `verify_jwt = false` nas duas funções com validação própria (bearer compartilhado; HMAC da Meta); toda RPC valida `auth_role()` (exceto `get_invite`/`accept_invite`); perfil inativado perde acesso imediatamente; `get_advisors` + pgTAP no CI; logs append-only; MFA na F2.

## Verificação

1. **Local:** `supabase start` → `supabase db reset` → `supabase gen types typescript --local` → `pnpm dev --experimental-https` (ou túnel) → `supabase functions serve --env-file supabase/.env.local`; `select * from net._http_response order by created desc limit 5` para os jobs.
2. **Seed:** usuários de teste do Passo 3 e unidade `teste`.
3. **Cadastro e roteamento:** logar como evangelista, cadastrar "João, Xaxim, alimento + cama, 3 filhos (15-17), número próprio" → 1 `strategy_review` + 1 `basic_food` + `home_items` na central; `message_log` com `transtornar_video1_v1`; mesmo cadastro com número "da família" → `transtornar_optin_v1`; mesmo telefone → `possible_duplicate` sem 2º `message_log`, depois `confirm_distinct_person` → opt-in endereçado a quem atende; mesmo `client_uuid` → `idempotent:true`; "Menor de 18" → só tally. Demais casos: "Pronto quando" dos Passos 4, 7 e 8.
4. **WhatsApp em sandbox:** número de teste da Meta + túnel: templates entregues nos dois modos; "Quero receber" → `journey_active` + vídeo 1; "Quero continuar" → `journey_active` + `video_watched`; `SAIR` → `skipped`; `sent/delivered/read` em `message_log`; webhook com `wa_id` sem 9º dígito resolve a pessoa; POST sem assinatura → 401.
5. **RLS (pgTAP):** os 8 arquivos; `central` de `curitiba` não vê `teste`; catálogo global visível nas duas unidades; `global_admin` lê tudo e escreve só no recorte definido; `team_member` inativado → zero linhas; evangelista lê `consent_text_v1` mas não `edge_base_url`.
6. **Testes a criar:** Vitest — `phone.test.ts` (E.164 e variante sem 9), `address.test.ts`, `schemas.test.ts` (chips de idade, consentimento), `referral-state.test.ts`; pgTAP — 8 arquivos; Deno — `whatsapp-send` (bearer, consentimento, quiet hours, escolha de template) e parser do webhook (assinatura, `dedup_key`, statuses repetidos, `wa_id` 12 vs 13 dígitos); Playwright local — `register-online.spec.ts`, `role-gate.spec.ts`.
7. **Piloto:** 5 evangelistas no Xaxim, 10 cadastros reais; medir mediana de preenchimento e critérios binários da F1.

## Perguntas em aberto para o cliente

1. Qual pessoa jurídica é o controlador (CNPJ)? Quem é o encarregado (DPO)?
2. Existe número/WhatsApp "Transtornar"? Quem terá acesso ao Business Manager?
3. Quantos evangelistas e quem opera a central no piloto (nomes, horário)?
4. Quais times existem hoje com pessoas reais (cesta, móveis, educação, trabalho, acompanhamento, estratégia)?
5. O vídeo inicial existe na plataforma legada? Quantos vídeos, formato, direitos? Há pessoas cadastradas nela?
6. "Esses pontos": marcos em dias ou pontuação acumulada trocável por prêmios?
7. O que é "integração da aba"?
8. Evangelistas ministram os cursos do Transtornar de educação (R-31a) ou o braço já tem turmas (R-31b)?
9. Periodicidade da cesta nos 3 meses, critério de renovação e quem entrega?
10. Em que formato está a base de empresas (planilha? quantas? há CNPJ?) e quem a mantém?
11. Uso previsto para o e-mail do convertido?
12. Confirma o padrão: vídeo 1 vai direto quando o número é da própria pessoa; mensagem neutra (sem citar Jesus) quando o número é de familiar/terceiro?
13. Adolescente evangelizado: aceita que na F1 só a contagem seja registrada (sem nome/telefone) até existir o fluxo com responsável?
14. A central quer ser avisada pelo painel (F1) ou exige aviso em grupo de WhatsApp/e-mail desde o piloto?
15. Aprova a lista de campos do formulário (tabela da §Formulário), em especial os cinco além dos que você citou: dono do número, idade, tipo de endereço, faixa por filho, consentimento?

## Rastreabilidade

| Requisitos | Onde no plano |
|---|---|
| R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-10, R-11, R-12 | Formulário; Modelo (003, `is_primary`, `confirm_distinct_person`); Fase 0 (e); Passos 6-7 |
| R-09 | Modelo (003 `households` na transação, só endereço fixo); mesclagem e programa por domicílio na Fase 2a |
| R-13 | LGPD; Modelo (`consents`, `people_contacts`, `audit_log`, `anonymize_person`); Passos 5, 7, 8, 10 |
| R-14, R-15, R-16, R-17 | Arquitetura; Roteamento (regras 5-50, motor idempotente); Passos 4, 8 (feed com nome para a central; canal → pergunta 14) |
| R-18 | Roteamento (referral `strategy_review` na fila unificada); digest e fila própria na Fase 2a após pergunta 4 |
| R-19, R-20, R-21 | Modelo (002, 004); Passo 8 (modo central única); notificação a times, SLA e Realtime na Fase 2a |
| R-22, R-23 | Adiado para Fase 2a (Haiku/Opus 5); `observation` à central na F1 |
| R-24, R-25, R-26, R-27 | Adiado para Fase 2a/2b (apêndice) |
| R-28 | Fase 2a (status de `delivery_orders` via `transtornar_entrega_v1` + selo em "Meus cadastros") |
| R-29, R-30, R-31, R-35, R-36 | Modelo (`children.age_band`, `wants_training`); regra 30 semeada inativa; operação na Fase 2b |
| R-32, R-33, R-34 | Modelo (`needs_job`, `occupation_area`); empresas/importação na Fase 2b |
| R-37, R-39, R-40 | Jornada (passos 0-V, 0-O, 0b, 1; `video_first` padrão para número próprio); Decisões; Passo 9 |
| R-38 | Fase 0 (d) inventário + `content_assets` (005); migração de pessoas e descontinuação na Fase 2b |
| R-41, R-42, R-43, R-46, R-47 | `people.stage` e `video_watched` na F1; série, `journey-tick` e feedback na Fase 2a |
| R-44 | Adiado para Fase 2b; depende da pergunta 7 |
| R-45 | F1: `inactive` + referral `follow_up` para contato humano (inclui sem WhatsApp); CRM na Fase 2a |
| R-48, R-49, R-50 | `reward_rules.condition_type` extensível; Fase 2a após pergunta 6 |
| R-51 | Modelo (001 bairros globais com aliases; views por bairro); Passos 3, 8 |
| R-52 | F1: contagem por bairro; Fase 2a: filtros por estágio/período e agregação por cidade |
| R-53 | Formulário (campo 3: faixa opcional na mesma linha do gate de maioridade) |
| R-54, R-55, R-60 | Colunas e coleta na Fase 2a/2b |
| R-56, R-65 | `v_impact_public` (k ≥ 5); relatório na Fase 3 / visão |
| R-57, R-58, R-59, R-61, R-62, R-63, R-64 | Fase 3 (segmentação por bairro/faixa/renda/segmento/estágio; métricas de mantenedores por faixa/renda/origem) |
| R-66 | Modelo (`units`, `unit_id NOT NULL`, `can_read_unit`, catálogos globais — ADR-004, `whatsapp_token_secret_name`, `clone_unit_defaults`, `isolation_second_unit.sql`); Passos 3, 5 |
| R-67 | Fase 4; strings já em `messages/pt-BR.json` |
