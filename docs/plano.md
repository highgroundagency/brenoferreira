# Transtornar — estado do sistema

Repositório `highgroundagency/brenoferreira` · branch `claude/new-session-jh3rio` · piloto Curitiba/PR.
Histórico do desenho original: `docs/plano-fase-1.md` (Fase 1) · requisitos em `docs/requisitos.md` · arquitetura em `docs/arquitetura.md` · decisões em `docs/adr/`.

As quatro fases previstas foram construídas. Este documento é o retrato do que existe hoje, o que está ligado na nuvem e o que ainda depende de você.

## O caminho da pessoa, ponta a ponta

1. **Cadastro (evangelista).** `/nova-pessoa`: nome, telefone com máscara e leitura de volta, e-mail, endereço com CEP, filhos por faixa etária, necessidade em chips ("comida", "itens de casa", "trabalho", "curso"), consentimento com texto versionado e passo de confirmação. Sem sinal, o cadastro entra numa fila local (Dexie) e sobe sozinho depois. Quem só quer contar decisões usa a contagem por bairro, sem PII.
2. **Central em tempo real.** `/central` mostra o feed ("mais uma pessoa aceitou Jesus no Xaxim — João, precisa de comida"), as filas por time, a ficha completa e a contagem por bairro. Realtime nas tabelas `people`, `referrals`, `notifications`, `delivery_orders`, `events`, `event_invitations`.
3. **Roteamento automático.** `apply_routing_rules` roda dentro da transação do cadastro: cesta básica, itens de casa, educação (filhos adolescentes), trabalho, acompanhamento e revisão de estratégia caem no time certo, com fallback para a central quando o time não tem gente.
4. **Primeiro contato no WhatsApp.** Conforme `units.settings.first_contact_mode`: vídeo 1 como header do template (`video_first`) ou template neutro de opt-in (`optin_first`, obrigatório quando o telefone é de terceiro). Fila em `message_log`, worker a cada minuto, quiet hours, revalidação de consentimento antes de cada envio.
5. **Jornada "primeiros passos da vida com Deus".** 11 passos (8 vídeos + 3 perguntas de perfil), botão "Assisti até o final", pergunta "o que achou", pontos, e os marcos de 7 e 16 dias que geram a entrega da Bíblia e do livrinho.
6. **Cuidado material.** Cesta básica por 3 meses vira um programa com entregas agendadas; itens de casa saem do estoque; cada entrega tem estados (separando, embalado, saiu para entrega, entregue, falhou) com aviso à família.
7. **Educação, trabalho e igreja.** Cursos e matrículas; empresas, vagas e colocações (com consentimento explícito antes de mandar o currículo para o empregador); sugestão e conexão com uma igreja do bairro.
8. **Bairro, eventos e empresários.** A cada 50%, 80% e 100% da meta do bairro a liderança é avisada; ao bater a meta, um evento nasce em rascunho. Convites segmentados por bairro, faixa etária, renda, segmento e estágio — só para quem consentiu receber convites — com RSVP e check-in por código.
9. **Mantenedores e clube de benefícios.** Funil de elegibilidade configurável, contribuições, parceiros, resgates e carteirinha pública (só primeiro nome).
10. **Franquia.** `create_unit(...)` abre uma unidade nova clonando times, regras, templates, jornada, marcos, pontos, elegibilidade e catálogo; `import_neighborhoods` traz os bairros de outra cidade; `v_units_comparison` compara as unidades. Textos em pt-BR e en, `locale` por unidade.

## O que está no ar

| Camada | Estado |
|---|---|
| Banco | Supabase `transtornar-prod` (`afdxoqccmljjqdcofspi`, `sa-east-1`, Free), migrations 001-014 aplicadas, dados de referência carregados |
| Jobs | 5 no `pg_cron`: envio (1 min), jornada (15 min), impacto (3h), retenção (seg 4h), limiares de bairro (5h) |
| Edge Functions | `whatsapp-send` e `whatsapp-webhook` publicadas (`verify_jwt = false`, cada uma valida bearer/assinatura) |
| Storage | Bucket público `content` criado; vídeo 1 ainda **inativo** (sem arquivo) |
| App | Build de produção verde; falta apontar o Vercel para o projeto |
| WhatsApp | Sem WABA: tudo que for enviar fica em fila, por desenho |

## LGPD

Convicção religiosa é dado sensível (art. 5º II; base legal: consentimento, art. 11 I). PII isolada em `people_contacts`, consentimento versionado por finalidade, `anonymize_person`, retenção que **nunca** anonimiza por silêncio (90 dias sem resposta vira contato humano; 24 meses sem nada ativo, aí sim anonimiza), `audit_log` em toda leitura de ficha. RIPD em `docs/lgpd/ripd.md`, operadores em `docs/lgpd/operadores.md`, política de retenção em `docs/lgpd/retencao.md`.

## Verificação

```
supabase/tests/local/run.sh    # 16 suítes pgTAP (225 checks) em Postgres local, sem Docker
pnpm vitest run                # 15 testes de domínio
pnpm exec biome check .        # 126 arquivos
pnpm build                     # build de produção
cd supabase/functions && deno test --allow-net --allow-env .   # 9 testes das Edge Functions (roda no CI)
```

## Pendências

Tudo o que depende de você — CNPJ e DPO, Business Manager e WABA, vídeos da jornada, credenciais do Vercel e as decisões de produto em aberto — está em `docs/pendencias.md`.
