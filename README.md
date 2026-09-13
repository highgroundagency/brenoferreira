# Transtornar

App do evangelista, central, jornada no WhatsApp, logística, eventos, mantenedores e franquia do movimento Transtornar (piloto: Curitiba/PR). Cliente: Breno Ferreira. Agência: High Ground.

- **Estado do sistema:** `docs/plano.md` · **O que depende de você:** `docs/pendencias.md`
- **Requisitos:** `docs/requisitos.md` · **Arquitetura:** `docs/arquitetura.md` · **ADRs:** `docs/adr/` · **LGPD:** `docs/lgpd/` · **Operação:** `docs/ops/runbook.md` · **Franquia:** `docs/ops/franquia.md`

## Stack
Next.js 15 (App Router, TypeScript, Tailwind 4) como PWA instalável · Supabase (Postgres 17, Auth, RLS, Storage, Edge Functions, `pg_cron` + `pg_net`, Realtime) · WhatsApp Cloud API oficial (Meta) · Biome, Vitest, Playwright, pgTAP, Deno test.

## O que existe
Cadastro em campo com fila offline e contagem por bairro · central em tempo real com feed, filas por time, ficha e acompanhamento · roteamento automático em SQL para cesta básica, itens de casa, educação, trabalho e estratégia · primeiro contato e jornada de 11 passos no WhatsApp com botões, feedback, pontos e os marcos de 7 e 16 dias · programa de cesta por 3 meses com entregas · cursos, empresas, vagas e colocações · igrejas · estoque de itens de casa · importação da plataforma legada · eventos por bairro com meta, convites segmentados, RSVP e check-in · mantenedores, contribuições, clube de benefícios e carteirinha pública · abertura de unidades novas clonando todos os catálogos (pt-BR e en).

## Rodando localmente
```
pnpm install
cp .env.example .env.local && cp supabase/.env.local.example supabase/.env.local
pnpm db:start && pnpm db:reset      # Docker: migrations 001-014 + seed (usuários *@test, senha Teste123!)
pnpm db:types                        # tipos do banco
pnpm dev                             # webpack (Serwist não suporta Turbopack); HTTPS: pnpm dev --experimental-https
pnpm fn:serve                        # Edge Functions (whatsapp-send, whatsapp-webhook)
```
Usuários locais: `evangelist@test`, `central@test`, `basic_food@test`, `unit_admin@test`, `global_admin@test`, `central_teste@test` (unidade `teste`).

Sem Docker: `supabase/tests/local/run.sh` valida migrations + seed + pgTAP em um Postgres 16 local (shim de auth/vault/cron/net) e `python3 scripts/gen-types.py > lib/database.types.ts` gera os tipos.

## Qualidade
```
pnpm lint          # biome (126 arquivos)
pnpm test          # vitest (domínio: telefone, endereço, schema do formulário, estados)
pnpm db:test       # pgTAP: 16 suítes, 225 checks — RLS por papel, isolamento de unidades, roteamento,
                   # register_person, anonimização, retenção, inbound, jornada, logística, mesclagem,
                   # educação/trabalho/igrejas/estoque, eventos/mantenedores/benefícios, franquia, grants
cd supabase/functions && deno test --allow-net --allow-env .
pnpm e2e           # Playwright local (opcional)
```

## Estrutura
```
app/(campo)      nova-pessoa, meus-cadastros
app/(central)    feed, filas/[teamKind], pessoas/[id], bairros, acompanhamento, entregas, educacao,
                 trabalho, igrejas, estoque, importar, impacto, eventos, mantenedores, beneficios, exportar
app/(admin)      usuarios, unidade, regras, jornada, marcos, conteudo, templates, unidades
app/(auth)       login, convite/[code], conta/seguranca        app/carteirinha/[code]  pública
lib/domain       phone, address, schemas (zod), referral-state  lib/offline  fila de reenvio (Dexie)
supabase/migrations 001-014   supabase/tests (pgTAP)   supabase/functions {whatsapp-send, whatsapp-webhook, _shared}
```

## Deploy
Vercel (região `gru1`) por integração Git; Supabase pelo workflow `.github/workflows/deploy.yml` (`db push`, `config push`, segredo do Vault, `functions deploy`). O projeto `transtornar-prod` (`afdxoqccmljjqdcofspi`, `sa-east-1`) já está com as migrations 001-014, os dados de referência, o bucket `content`, os 5 jobs do `pg_cron` e as duas Edge Functions publicadas — falta ligar a WABA e as credenciais. Passo a passo, diagnóstico e teste de fumaça em `docs/ops/runbook.md`; WhatsApp (WABA, templates, sandbox) em `docs/ops/whatsapp.md`.
