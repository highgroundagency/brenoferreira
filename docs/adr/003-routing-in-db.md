# ADR-003 — Roteamento e enfileiramento dentro da transação do banco

**Decisão.** `register_person` (plpgsql, security definer) insere pessoa/PII/filhos/necessidades/consentimentos, chama `apply_routing_rules` e enfileira o primeiro contato em `message_log` na mesma transação. Sem outbox, sem Database Webhook, sem n8n. Só duas Edge Functions: `whatsapp-send` (worker a cada minuto via `pg_cron` + `pg_net`) e `whatsapp-webhook`.

**Por quê.** Dezenas de cadastros por semana; uma lógica em um runtime, testada em pgTAP (`routing.sql`, `register_person.sql`). Idempotência por `client_uuid` (fila offline) e por `(referral_type, need_id)` no motor.

**Consequências.** Regras vivem em `routing_rules` (globais com `unit_id null`, clonáveis por unidade). Nova necessidade registrada pela central reexecuta o motor via trigger `needs_route`. Se a IA entrar no roteamento (Fase 2a), ela roda em job separado sobre `needs.raw_text` com `detected_by='ai'`.
