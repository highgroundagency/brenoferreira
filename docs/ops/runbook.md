# Runbook — desenvolvimento e operação

## Local (com Docker)
```
pnpm install && cp .env.example .env.local && cp supabase/.env.local.example supabase/.env.local
pnpm db:start && pnpm db:reset          # migrations 001-007 + seed.sql (usuários *@test, senha Teste123!)
pnpm db:types                            # lib/database.types.ts
pnpm dev --experimental-https            # PWA precisa de HTTPS para instalar; ou: cloudflared tunnel --url http://localhost:3000
pnpm fn:serve                            # Edge Functions com supabase/.env.local
pnpm db:test                             # pgTAP (9 suítes)
```
`seed.sql` grava `app_settings.edge_base_url` apontando para `http://host.docker.internal:54321/functions/v1`; ajuste se o Postgres do CLI não alcançar o host (Linux: `172.17.0.1`). Verifique os jobs com `select * from net._http_response order by created desc limit 5;` e `select * from cron.job;`.

## Local (sem Docker)
`supabase/tests/local/run.sh` cria um banco em um Postgres 16 local com shim de `auth`/`vault`/`cron`/`net`, aplica migrations + seed e roda os pgTAP. Tipos: `python3 scripts/gen-types.py > lib/database.types.ts`.

## Produção (primeira vez)
1. Projeto Supabase `transtornar-prod` em `sa-east-1` (Free no desenvolvimento; Pro antes do piloto: timebox de sessão, sem pausa por inatividade, backups). Habilitar `pg_cron` e `pg_net` em Database → Extensions (a migration 001 cria se disponíveis).
2. `supabase link --project-ref <ref>` → `supabase db push` → `supabase config push` (confirmação de e-mail desligada, timebox 720h, SMTP Resend em Auth → SMTP).
3. `psql "$DATABASE_URL" -f supabase/seeds/prod.sql` (edge_base_url, vídeo 1, templates espelhados) e criação única do segredo:
   `psql "$DATABASE_URL" -v secret="$EDGE_SHARED_SECRET" -c "select vault.create_secret(:'secret','edge_shared_secret') where not exists (select 1 from vault.secrets where name='edge_shared_secret')"`.
4. `supabase secrets set EDGE_SHARED_SECRET=… WHATSAPP_ACCESS_TOKEN=… WHATSAPP_APP_SECRET=… WHATSAPP_VERIFY_TOKEN=… WHATSAPP_API_VERSION=v24.0` e `supabase functions deploy whatsapp-send whatsapp-webhook --no-verify-jwt`.
5. Bucket público `content` no Storage; `update units set whatsapp_phone_number_id=…, whatsapp_waba_id=… where slug='curitiba'`.
6. Webhook na Meta: `https://<ref>.supabase.co/functions/v1/whatsapp-webhook`, verify token = `WHATSAPP_VERIFY_TOKEN`, campos `messages`, `message_template_status_update`, `template_category_update`, `phone_number_quality_update`.
7. Primeiro admin: inserir `profiles` (role `unit_admin`) para o usuário criado no dashboard Auth; depois convites pelo app.
8. Vercel: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_APP_URL`; região `gru1`.

## Diagnóstico
- Mensagem não saiu: `select id, status, skip_reason, error_code, error_message, scheduled_for from message_log order by created_at desc limit 20;`
- Cron não chama a função: `select * from net._http_response order by created desc limit 5;` (401 = bearer do Vault ≠ `EDGE_SHARED_SECRET`).
- Webhook: `select event_type, error, created_at from wa_inbound_events order by created_at desc limit 20;` (assinatura inválida → 401 nos logs da função).
- Pessoa com telefone repetido: ficha → "Marcar duplicata" ou "Mesma casa, pessoa diferente".
