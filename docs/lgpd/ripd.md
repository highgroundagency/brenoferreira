# RIPD — Relatório de Impacto à Proteção de Dados (Fase 1, v1)

**Controlador:** pessoa jurídica do Transtornar (CNPJ e encarregado/DPO a nomear — Fase 0 a). **Operadora:** High Ground Agency. **Sub-operadores:** Supabase (banco e Edge Functions em `sa-east-1`), Vercel (app, região `gru1`), Meta (WhatsApp Cloud API — transferência internacional, art. 33), Resend (e-mail transacional do Auth).

**Natureza dos dados.** Existir em `people` = dado pessoal sensível (convicção religiosa, art. 5º, II). Também: nome, telefone, endereço (`people_contacts`), quantidade e faixa etária de filhos (sem nome), necessidades sociais, situação de trabalho. Não coletados: CPF, data de nascimento, renda (Fase 2 via WhatsApp), GPS do evangelista, foto.

**Base legal.** Consentimento específico e destacado (art. 11, I), colhido pelo evangelista com roteiro lido em voz alta + checkbox, versionado (`consents`, `consent_text_version`, `collected_by`, `client_uuid`). Finalidades separadas: `spiritual_followup`, `whatsapp_contact` (também vale como opt-in da Meta), `social_assistance` (só com necessidade declarada). Igreja/empresa/eventos só por novo consentimento por botão no WhatsApp (Fase 2+).

**Menores.** Fase 1 cadastra só maiores de 18; adolescentes evangelizados entram apenas na contagem anônima (`decision_tally.minor_count`). Fluxo com responsável presente na Fase 2a (art. 14).

**Minimização por papel (RLS + RPCs).** Evangelista não lê a base: só `get_my_registrations()` (telefone some após 30 dias). Times leem só a própria fila por `get_team_queue()` (sem e-mail/observação). Central/unit_admin leem a unidade; abrir ficha grava `audit_log`. `global_admin` só leitura. Relatórios externos com k ≥ 5 (`v_impact_public`).

**Direitos.** `SAIR` → opt-out imediato; `MEUS DADOS` → pedido registrado com prazo de 15 dias; anonimização por `anonymize_person` (apaga PII de todas as tabelas, mantém bairro/estágio para métricas). Retenção: ver `retencao.md` — **nunca anonimização por silêncio**.

**Riscos e mitigações.** Número errado/de terceiro recebe conteúdo religioso → modo `optin_first` (template neutro) para `phone_owner <> self`, read-back do número antes de enviar; vazamento → PII em tabela própria, RLS testada em pgTAP, segredos só em Vault/Secrets; envio sem consentimento → `whatsapp-send` revalida consentimento e estágio a cada envio (zero envio sem `consents.whatsapp_contact`).
