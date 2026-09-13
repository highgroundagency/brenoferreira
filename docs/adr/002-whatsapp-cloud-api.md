# ADR-002 — WhatsApp pela Cloud API oficial da Meta, atrás de `WhatsAppProvider`

**Decisão.** Toda mensagem sai pela WhatsApp Business Platform (Cloud API), integração direta sem BSP, com a WABA e o número em nome do **Transtornar** (controlador) e a agência como parceira/operadora. Provedores não oficiais (Z-API, Evolution API) são proibidos. O provedor fica atrás da interface `supabase/functions/_shared/whatsapp/provider.ts` (`MetaCloudProvider`), para trocar por um BSP sem tocar na jornada.

**Primeiro contato.** `units.settings.first_contact_mode` com dois modos implementados: `video_first` (padrão quando `phone_owner='self'`): template com header de vídeo e corpo neutro; `optin_first` (obrigatório para `family|other`): template neutro, vídeo 1 só após "Quero receber". O consentimento colhido no app (roteiro + checkbox, versionado) é o opt-in exigido pela Meta; a categoria dos templates é espelhada da Graph API (orçar como MARKETING).

**Consequências.** Templates precisam de aprovação (Fase 0 c); pessoas sem WhatsApp (erro 131026) vão para contato humano; quiet hours 21h-08h; `SAIR` bloqueia em < 1 min; nada sai sem `consents.whatsapp_contact` ativo.
