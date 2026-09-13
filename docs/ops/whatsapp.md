# WhatsApp — Fase 0 (b/c) e testes em sandbox

1. Meta Business Portfolio **do Transtornar**; Business Verification iniciada; app tipo Business com produto WhatsApp; WABA; número dedicado (nunca usado em WhatsApp comum); display name aprovado; agência adicionada como parceira.
2. Token permanente de System User com `whatsapp_business_messaging` e `whatsapp_business_management` → `WHATSAPP_ACCESS_TOKEN`. Inscrever o app na WABA: `POST /{waba_id}/subscribed_apps`.
3. Templates (pt_BR) a submeter, com os mesmos nomes de `message_templates`:
   - `transtornar_video1_v1` — header VIDEO, corpo "Olá {{1}}! Aqui é o Transtornar. Preparamos este vídeo para você. Para parar a qualquer momento, responda SAIR.", quick replies "Quero continuar" / "Parar".
   - `transtornar_optin_v1` — corpo "Olá {{1}}! Aqui é o Transtornar. Registramos seu contato hoje. Quer receber nossas mensagens e vídeos? Para parar, responda SAIR.", quick replies "Quero receber" / "Agora não".
   - `transtornar_lembrete_v1` — corpo "Olá {{1}}, aqui é o Transtornar de novo. Quer receber nossas mensagens? Para parar, responda SAIR.", mesmos botões.
   A ordem dos botões precisa ser a mesma de `message_templates.buttons` (o worker envia o `payload` de cada quick reply por índice).
4. Espelhar status/categoria: `GET /{waba_id}/message_templates?fields=name,language,status,category` → `seeds/prod.sql` ou o webhook `message_template_status_update`.
5. Sandbox: com o app em desenvolvimento só é possível enviar para até 5 números de teste. Fluxo: `pnpm fn:serve` + `cloudflared tunnel --url http://localhost:54321` → configurar o webhook na Meta com a URL do túnel `/functions/v1/whatsapp-webhook`; cadastrar uma pessoa com número de teste; conferir `message_log` → `sent/delivered/read`; clicar nos botões e conferir `person_events`/`stage`; responder `SAIR` e conferir `skipped`.
6. Live: Business Verification concluída, número registrado, templates aprovados; teste com 3 números reais fora da lista de teste.
