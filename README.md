# Transtornar

App do evangelista, central e primeiro contato via WhatsApp do movimento Transtornar (piloto: Curitiba/PR). Cliente: Breno Ferreira. Agência: High Ground.

- **Plano da Fase 1:** `docs/plano-fase-1.md` · **Requisitos:** `docs/requisitos.md` · **Arquitetura:** `docs/arquitetura.md` · **ADRs:** `docs/adr/` · **LGPD:** `docs/lgpd/` · **Operação:** `docs/ops/runbook.md`

## Stack
Next.js 15 (App Router, TypeScript, Tailwind 4) como PWA instalável · Supabase (Postgres 17, Auth, RLS, Storage, Edge Functions, `pg_cron` + `pg_net`) · WhatsApp Cloud API oficial (Meta) · Biome, Vitest, Playwright, pgTAP, Deno test.

## Rodando localmente
```
pnpm install
cp .env.example .env.local && cp supabase/.env.local.example supabase/.env.local
pnpm db:start && pnpm db:reset      # Docker: migrations 001-007 + seed (usuários *@test, senha Teste123!)
pnpm db:types                        # tipos do banco
pnpm dev                             # webpack (Serwist não suporta Turbopack); HTTPS: pnpm dev --experimental-https
pnpm fn:serve                        # Edge Functions (whatsapp-send, whatsapp-webhook)
```
Usuários locais: `evangelist@test`, `central@test`, `basic_food@test`, `unit_admin@test`, `global_admin@test`, `central_teste@test` (unidade `teste`).

Sem Docker: `supabase/tests/local/run.sh` valida migrations + seed + pgTAP em um Postgres 16 local (shim de auth/vault/cron/net) e `python3 scripts/gen-types.py > lib/database.types.ts` gera os tipos.

## Qualidade
```
pnpm lint          # biome
pnpm test          # vitest (domínio: telefone, endereço, schema do formulário, estados)
pnpm db:test       # pgTAP: RLS por papel, isolamento de unidades, register_person, roteamento, anonimização, retenção, inbound
cd supabase/functions && deno test --allow-net --allow-env .
pnpm e2e           # Playwright local (opcional)
```

## Estrutura
```
app/(campo)      nova-pessoa, meus-cadastros        app/(central)  feed, filas/[teamKind], pessoas/[id], bairros
app/(admin)      usuarios (convites)                 app/(auth)     login, convite/[code]
lib/domain       phone, address, schemas (zod), referral-state      lib/offline  fila de reenvio (Dexie)
supabase/migrations 001-007   supabase/tests (pgTAP)   supabase/functions {whatsapp-send, whatsapp-webhook, _shared}
```

## Deploy
Vercel (região `gru1`) por integração Git; Supabase pelo workflow `.github/workflows/deploy.yml` (`db push`, `config push`, segredo do Vault, `functions deploy`). Passo a passo da primeira vez, variáveis e diagnóstico em `docs/ops/runbook.md`; WhatsApp (WABA, templates, sandbox) em `docs/ops/whatsapp.md`.

## Fase 0 (pré-requisitos do piloto)
CNPJ/DPO e textos de consentimento; Business Manager + WABA + número do Transtornar e templates submetidos; vídeo 1 no bucket `content`; respostas às perguntas ao cliente (`docs/plano-fase-1.md`); protótipo testado com 3 evangelistas.
