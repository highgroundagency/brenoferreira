# Registro de operadores e fluxos de dados

| Operador | Papel | Dados | Região | Base contratual |
|---|---|---|---|---|
| Supabase | banco, auth, storage, edge functions, cron | todos | sa-east-1 (Edge com `x-region: sa-east-1`) | DPA Supabase |
| Vercel | hospedagem do app | sessão (cookies), telas | gru1 | DPA Vercel |
| Meta (WhatsApp Cloud API) | envio/recebimento de mensagens | telefone, primeiro nome, vídeo, respostas | internacional (art. 33) | termos WhatsApp Business |
| Resend | e-mail transacional do Auth (senha) | e-mail do voluntário | EUA | DPA Resend |
| High Ground Agency | operadora (desenvolvimento e operação) | acesso administrativo | Brasil | contrato de prestação de serviço |

Fluxo: evangelista (PWA) → `register_person` (Postgres) → `message_log` → `whatsapp-send` (Edge) → Meta → pessoa; respostas → Meta → `whatsapp-webhook` → `handle_inbound` (Postgres). Acesso da agência ao projeto de produção: apenas por convite `unit_admin`/`global_admin` nomeado, com `audit_log`.
