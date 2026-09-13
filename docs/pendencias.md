# O que depende de você

Tudo o que o sistema podia fazer sozinho está feito. O que sobra é de três tipos: coisas que só você pode contratar ou assinar, coisas que precisam de credencial, e decisões de produto que eu tomei com um padrão razoável e que você confirma ou muda. Nada aqui exige mexer em código — as decisões de produto são configuração no `/admin`.

## 1. Bloqueia o piloto

| # | O quê | Por quê | Quem |
|---|---|---|---|
| 1 | **CNPJ e DPO** do Transtornar (ou da associação/igreja que responde pela base) | Convicção religiosa é dado sensível; alguém precisa figurar como controlador no texto de consentimento e no RIPD (`docs/lgpd/ripd.md`) | Você |
| 2 | **Business Manager + WABA + número** em nome do Transtornar (agência entra como parceira) | Sem WABA nada sai; o sistema já enfileira tudo e envia sozinho no minuto seguinte à ligação | Você (eu configuro) |
| 3 | **Templates submetidos à Meta** (12 já cadastrados no banco, texto pronto) | Aprovação leva de horas a dias; o webhook já espelha o status automático | Você aprova o texto, eu submeto |
| 4 | **Vídeo 1** ("a importância de Jesus") em mp4 | Hoje está inativo de propósito — sem arquivo, o primeiro contato sairia com link quebrado. Subir no bucket `content` como `video_1.mp4` e ativar (comando no runbook) | Você manda o arquivo |
| 5 | **Vídeos 2 a 8** da jornada | Cada passo sem vídeo é pulado e registrado; a jornada anda, mas capenga | Você |
| 6 | **Credenciais do Vercel** (ou me autorizar a criar o projeto) | É o que falta para o app ficar no ar | Você |
| 7 | **Secrets no GitHub**: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF` (`afdxoqccmljjqdcofspi`), `EDGE_SHARED_SECRET` | O workflow de deploy cria o segredo do Vault e publica as funções com o mesmo valor dos dois lados. Não pus nenhum segredo no repositório de propósito | Você |
| 8 | **Primeiro usuário admin** | Crio o usuário em Auth e o `profiles` com papel `unit_admin`; daí em diante os convites saem pelo app | Eu, assim que você disser o e-mail |
| 9 | **3 evangelistas para testar** o formulário em campo antes do piloto | É o teste que vale: se demorar mais de um minuto, corto campos | Você |

## 2. Decisões que tomei — confirme ou mude

Cada uma está implementada com o padrão da coluna do meio e é configurável no `/admin` sem tocar em código.

| Decisão | O que está valendo | Alternativa |
|---|---|---|
| **Primeiro contato** | `video_first`: o vídeo 1 vai como cabeçalho do template, com o botão "Assisti até o final". Se o telefone for de familiar/terceiro, o modo vira `optin_first` (mensagem neutra, vídeo só depois do "quero receber") | Sempre `optin_first` — mais conservador com a Meta, menos fiel ao que você descreveu |
| **Renda** | Perguntada pelo WhatsApp no 8º passo da jornada, não no cadastro em campo | Perguntar no cadastro (mais completo, mais constrangedor na hora da conversão) |
| **Faixa etária** | Select opcional no cadastro | Perguntar depois, como a renda |
| **E-mail** | Opcional | Obrigatório |
| **Necessidade** | Chips fechados (comida, itens de casa, trabalho, curso) + observação livre para a central | Texto livre classificado por IA |
| **Cesta básica** | 3 meses, 1 entrega a cada 30 dias, **por domicílio** (duas pessoas da mesma casa não geram duas cestas) | Por pessoa; outra duração/frequência |
| **Educação** | Dispara com filho de 12 a 17 anos | Incluir crianças menores |
| **Telefone repetido** | Não bloqueia: cria com alerta na central, que decide entre "é duplicata" e "mesma casa, pessoa diferente" | Bloquear no cadastro |
| **Gamificação** | Marcos por dias de conteúdo (4 passos ≈ 7 dias → Bíblia; 8 passos ≈ 16 dias → livrinho) **e** pontos acumulados em paralelo (vídeo 10, feedback 5, resposta 5, igreja 20, presença em evento 20) | Só marcos, ou só pontos com resgate por saldo |
| **Meta do bairro** | 2.000 decisões; avisos em 50% e 80%; ao bater, o evento nasce em rascunho (nunca dispara convite sozinho) | Outro número, por bairro |
| **Horário de silêncio** | Não envia entre 21h e 8h; primeiro contato com 10 minutos de atraso | Outro intervalo |
| **Mantenedores** | Elegibilidade por regra configurável: empresário/autônomo, renda acima de 3 salários, ou quem concluiu a jornada | Só empresários |
| **Pagamento das contribuições** | Registrado no sistema, cobrado fora dele (Pix/link) | Integrar gateway (não recomendo agora: vira meio de pagamento, muda o risco regulatório) |
| **Retenção** | 90 dias sem resposta → contato humano, nunca exclusão; 24 meses sem nada ativo → anonimização; quem pede SAIR é anonimizado em 30 dias | Outros prazos |
| **IA no WhatsApp** | Desligada (`ai_enabled: false`). O texto livre que chega abre acompanhamento humano | Ligar a classificação e o assistente (Fase 2c) |
| **Instrutores dos cursos** | Modelei `volunteer_availability` (dia, turno, competências) assumindo que os evangelistas ministram | Se o "Transtornar de educação" é um parceiro externo com vagas, simplifico |

## 3. Custo hoje

Supabase Free: **R$ 0/mês**. Antes do piloto vale subir para o Pro (US$ 25/mês por projeto) — sem pausa por inatividade, backups diários e sessão sem timebox. Vercel Hobby resolve o começo. O WhatsApp cobra por conversa iniciada (as da jornada entram como marketing); a estimativa por volume está em `docs/ops/whatsapp-pricing.md`, e há teto configurável de mensagens por mês na unidade.

## 4. Limitações conhecidas

- **Nada foi enviado por WhatsApp ainda** — sem WABA, por desenho. O caminho todo está testado em banco (225 checks), não contra a API da Meta.
- **Teste de fumaça das Edge Functions**: as funções estão publicadas, mas o proxy de saída deste ambiente bloqueia `*.supabase.co`, então não consegui bater nelas por HTTP daqui. Os quatro `curl` que provam as respostas 401/403/401/405 estão no runbook; rode depois do deploy.
- **Testes Deno** (9, das Edge Functions) não rodaram nesta rodada: o binário não está neste contêiner e o download está bloqueado pelo proxy. Rodam no CI a cada push (`.github/workflows/ci.yml`).
- **Playwright** só local; não faz parte do CI.
- **`multiple_permissive_policies`**: as políticas `..._write` são `for all`, o que soma um `select` permissivo. Diferença de plano irrelevante no volume do piloto; deixei documentado em vez de reescrever 15 políticas testadas.
- **Vídeo 1 inativo** até o arquivo existir — é o que impede um primeiro contato quebrado.
