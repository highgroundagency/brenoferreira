# Política de retenção (Fase 1) — `run_retention_policy()` roda semanalmente

| Situação | Regra | Fase |
|---|---|---|
| Sem resposta ao primeiro contato após lembrete + 14 dias | `stage='inactive'` + encaminhamento `follow_up` (contato humano) + `contact_attempt` — **nunca anonimização por silêncio** | 1 |
| `SAIR` / botão Parar / "Agora não" explícito | opt-out imediato (`consents.revoked_at`, fila bloqueada); anonimização 30 dias depois | 1 |
| Pedido do titular (`MEUS DADOS`, central) | registrado em `person_events(data_request)`, prazo 15 dias; `anonymize_person` | 1 |
| Número sem WhatsApp (131026) | `whatsapp_valid=false` + `follow_up` imediato (ligar/visitar); sem prazo de anonimização | 1 |
| "Agora não" + 90 dias sem interação | `inactive` + `follow_up` (não anonimiza) | 2a |
| 24 meses sem qualquer interação **e** sem programa/encaminhamento/matrícula ativo | anonimização | 2a |
| `wa_inbound_events.raw` | 90 dias | 1 |
| `consents`, `audit_log` | 5 anos (diff anonimizado junto com a pessoa) | 1 |
