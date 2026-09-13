# Runbook — desenvolvimento e operação

## Local (com Docker)
```
pnpm install && cp .env.example .env.local && cp supabase/.env.local.example supabase/.env.local
pnpm db:start && pnpm db:reset          # migrations 001-007 + seed.sql (usuários *@test, senha Teste123!)
pnpm db:types                            # lib/database.types.ts
pnpm dev --experimental-https            # PWA precisa de HTTPS para instalar; ou: cloudflared tunnel --url http://localhost:3000
pnpm fn:serve                            # Edge Functions com supabase/.env.local
pnpm db:test                             # pgTAP (16 suítes)
```
`seed.sql` grava `app_settings.edge_base_url` apontando para `http://host.docker.internal:54321/functions/v1`; ajuste se o Postgres do CLI não alcançar o host (Linux: `172.17.0.1`). Verifique os jobs com `select * from net._http_response order by created desc limit 5;` e `select * from cron.job;`.

## Local (sem Docker)
`supabase/local-harness/run.sh` cria um banco em um Postgres 16 local com shim de `auth`/`vault`/`cron`/`net`, aplica migrations + seed e roda os pgTAP. Tipos: `python3 scripts/gen-types.py > lib/database.types.ts`.

## Produção — estado atual (13/09/2026)

Projeto **`transtornar-prod`** (`afdxoqccmljjqdcofspi`, `sa-east-1`, plano Free — R$ 0/mês) já provisionado por MCP:

- migrations 001-014 aplicadas (`supabase migration list` confere com `supabase/migrations/`);
- dados de referência: 75 bairros de Curitiba, 8 times, 6 regras de roteamento, 11 passos da jornada, 12 templates, texto de consentimento v1;
- `app_settings.edge_base_url` = `https://afdxoqccmljjqdcofspi.supabase.co/functions/v1`;
- bucket público `content` (100 MB por arquivo, mp4/mov/jpg/png/webp/pdf; escrita só para `unit_admin`/`global_admin`);
- 5 jobs no `pg_cron`: `whatsapp-send` (1 min), `journey-tick` (15 min), `impact-refresh` (3h), `lgpd-retention` (seg 4h), `event-thresholds` (5h);
- Edge Functions `whatsapp-send` e `whatsapp-webhook` publicadas com `verify_jwt = false` (cada uma valida bearer/assinatura por conta própria);
- `get_advisors` sem ERROR: sobram avisos esperados (as 48 RPCs do painel e as 2 públicas são a API desenhada; `pg_net` aparece como "extensão em public", mas as 12 funções dela vivem no schema `net`).

**Ainda falta ligar** (depende de credenciais que não estão neste repositório):

1. Bearer das Edge Functions: **feito** — o segredo `edge_shared_secret` foi gerado dentro do banco e guardado no Vault. Falta só espelhá-lo no lado da função: Dashboard → Edge Functions → Secrets → `EDGE_SHARED_SECRET`, com o valor lido em Dashboard → SQL Editor:
   `select decrypted_secret from vault.decrypted_secrets where name = 'edge_shared_secret';`
   O workflow `deploy.yml` faz isso sozinho a cada deploy (lê do Vault e chama `supabase secrets set`), então esse passo manual só vale se você quiser ligar o envio antes do próximo deploy. Enquanto os dois lados não tiverem o mesmo valor, o cron recebe 401 e nada é enviado — que é o comportamento desejado antes da WABA.
2. `supabase secrets set WHATSAPP_ACCESS_TOKEN=… WHATSAPP_APP_SECRET=… WHATSAPP_VERIFY_TOKEN=… WHATSAPP_API_VERSION=v24.0`.
3. `update public.units set whatsapp_phone_number_id = '…', whatsapp_waba_id = '…' where slug = 'curitiba';` — sem isso o worker não tem unidade para processar.
4. Webhook na Meta: `https://afdxoqccmljjqdcofspi.supabase.co/functions/v1/whatsapp-webhook`, verify token = `WHATSAPP_VERIFY_TOKEN`, campos `messages`, `message_template_status_update`, `template_category_update`, `phone_number_quality_update`.
5. Vídeo 1 no bucket `content` como `video_1.mp4` e então:
   `update public.content_assets set rights_ok = true, active = true where key = 'video_1';` (hoje está inativo de propósito: sem arquivo, o primeiro contato seria enviado com um link quebrado).
6. Primeiro admin: criar o usuário em Auth → Users e inserir o `profiles` correspondente com `role = 'unit_admin'` e a unidade `curitiba`; daí em diante os convites saem pelo app.
7. Vercel: `NEXT_PUBLIC_SUPABASE_URL = https://afdxoqccmljjqdcofspi.supabase.co`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (Settings → API Keys → publishable), `NEXT_PUBLIC_APP_URL`; região `gru1`.

Teste de fumaça depois do deploy (deve dar 401, 403, 401 e 405, nessa ordem):
```
B=https://afdxoqccmljjqdcofspi.supabase.co/functions/v1
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$B/whatsapp-webhook" -H 'content-type: application/json' -d '{"entry":[]}'
curl -s -o /dev/null -w '%{http_code}\n' "$B/whatsapp-webhook?hub.mode=subscribe&hub.verify_token=errado&hub.challenge=123"
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$B/whatsapp-send"
curl -s -o /dev/null -w '%{http_code}\n' "$B/whatsapp-send"
```

## Produção (do zero, em outra unidade ou projeto)
1. Projeto Supabase em `sa-east-1` (Free no desenvolvimento; Pro antes do piloto: timebox de sessão, sem pausa por inatividade, backups). Habilitar `pg_cron` e `pg_net` em Database → Extensions (a migration 001 cria se disponíveis).
2. `supabase link --project-ref <ref>` → `supabase db push` → `supabase config push` (confirmação de e-mail desligada, timebox 720h, SMTP Resend em Auth → SMTP).
3. `psql "$DATABASE_URL" -f supabase/seeds/prod.sql` (edge_base_url, vídeo 1, templates espelhados). O bearer das Edge Functions não precisa de passo manual: o `deploy.yml` gera no Vault se não existir e espelha nas funções.
4. `supabase secrets set WHATSAPP_ACCESS_TOKEN=… WHATSAPP_APP_SECRET=… WHATSAPP_VERIFY_TOKEN=… WHATSAPP_API_VERSION=v24.0` e `supabase functions deploy whatsapp-send whatsapp-webhook --no-verify-jwt`.
5. Bucket público `content` no Storage; `update units set whatsapp_phone_number_id=…, whatsapp_waba_id=… where slug='curitiba'`.
6. Webhook na Meta (campos acima) e primeiro admin em `profiles`.
7. Vercel: variáveis acima, região `gru1`.
8. Unidades novas (franquia): `select public.create_unit('joinville','Transtornar Joinville','Joinville','SC','4209102')` como `global_admin` — clona times, regras, templates, jornada, marcos, pontos, elegibilidade e catálogo. Playbook completo em `docs/ops/franquia.md`.

## Diagnóstico
- Mensagem não saiu: `select id, status, skip_reason, error_code, error_message, scheduled_for from message_log order by created_at desc limit 20;`
- Cron não chama a função: `select * from net._http_response order by created desc limit 5;` (401 = bearer do Vault ≠ `EDGE_SHARED_SECRET`).
- Webhook: `select event_type, error, created_at from wa_inbound_events order by created_at desc limit 20;` (assinatura inválida → 401 nos logs da função).
- Pessoa com telefone repetido: ficha → "Marcar duplicata" ou "Mesma casa, pessoa diferente".

## Rotação do bearer das Edge Functions
O Vault é a fonte única: o `deploy.yml` lê de lá e espelha nas Edge Functions, então não existe
segredo equivalente no GitHub para sair do lugar. Para rotacionar, troque no Vault e rode o deploy:

```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'edge_shared_secret'),
  encode(extensions.gen_random_bytes(32), 'hex')
);
```

Entre a troca e o deploy seguinte, o `pg_cron` manda o bearer novo para uma função que ainda espera o
antigo e os envios voltam 401 — visível em `select * from net._http_response order by created desc`.

## Unidade de demonstração
Existe uma unidade `demo` ("Transtornar Demonstração") com 10 pessoas fictícias, jornada em
andamento, cestas, entregas, matrícula, contratação, igreja, evento de bairro disparado por meta e
mantenedores — criada pelas próprias funções do sistema, para mostrar as telas com vida. Ela é
isolada da unidade `curitiba` pela RLS: a conta de visualização não enxerga nenhuma pessoa real.

Acesso: `demo@transtornar.app` (a senha fica fora do repositório; troque em Authentication → Users).
Para remover tudo de uma vez, incluindo os usuários da demonstração:

```sql
delete from public.units where slug = 'demo';
```

## Advisors e endurecimento
`get_advisors` (segurança e desempenho) roda no painel do Supabase e pelo MCP. O que já foi tratado:

- **migrations 012-013**: as funções criadas nas migrations 009-011 nasceram depois do `revoke ... from anon` da 008 e estavam executáveis por `anon` via `/rest/v1/rpc/*` — a lista de execução foi refeita do zero (só as RPCs do painel para `authenticated`; `get_invite`, `normalize_text` e `supporter_card` para `anon`), `event_audience`, `supporter_candidates`, `suggest_church` e `refresh_impact` ganharam guarda de papel, `search_path` foi fixado em todas as funções e a `mv_impact` saiu para o schema `private` (fora do PostgREST), com as visões filtrando por unidade.
- **migration 014**: `auth.uid()` dentro das políticas de RLS virou `(select auth.uid())` (uma avaliação por consulta em vez de uma por linha) e as FKs quentes ganharam índice.
- `supabase/tests/grants.sql` trava a regressão: qualquer função nova que volte a ficar pública quebra a suíte.

Avisos que ficam de propósito: as 48 RPCs `security definer` que o painel chama (cada uma valida papel e unidade no corpo), as 2 públicas (`get_invite`, `supporter_card`, ambas só respondem com um código válido) e `multiple_permissive_policies` (as políticas `..._write` são `for all`, o que soma um `select` permissivo ao `..._select`; a diferença de plano é irrelevante no volume do piloto).
