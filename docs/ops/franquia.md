# Abrir uma nova unidade (franquia)

Uma unidade é uma cidade do Transtornar. Tudo é isolado por `unit_id` (RLS provada em `isolation_second_unit.sql` e `phase4.sql`): pessoas, times, filas, jornada, eventos, mantenedores e métricas.

## 1. Antes de abrir (responsabilidade do Transtornar)
- Definir o responsável local (vira `unit_admin`) e quem opera a central.
- Conta da Meta: **cada unidade precisa do próprio número e da própria WABA** (ou de um número adicional na mesma WABA) e da aprovação dos templates — eles são clonados com status `pending`.
- Conferir a base legal: o controlador continua sendo a PJ do Transtornar; se a unidade for outra pessoa jurídica, refazer o RIPD e o registro de operadores (`docs/lgpd/`).

## 2. Abrir no sistema (`/admin/unidades`, só `global_admin`)
1. Identificador (slug), nome, cidade, UF, código IBGE (opcional) e idioma.
2. A unidade nasce com: 8 times (central, cesta básica, acompanhamento e estratégia ativos), as regras de roteamento, os 11 passos da jornada, os marcos de 7 e 16 dias, as regras de pontos e de elegibilidade a mantenedor, o catálogo de itens e o texto de consentimento vigente.
3. Importar os bairros da cidade (CSV com `name`, `aliases` separados por `|`, `region`). Fonte: lista oficial da prefeitura ou do IBGE.
4. Em `/admin/unidade`, preencher `whatsapp_phone_number_id`, `whatsapp_waba_id`, fuso, horário de silêncio, meses de cesta e o modo do primeiro contato.
5. Publicar os vídeos da jornada em `/admin/conteudo` (podem ser os mesmos da unidade piloto, se os direitos permitirem).
6. Convidar a equipe em `/admin/usuarios`; o primeiro convite deve ser o `unit_admin` local.

## 3. Ajustes locais permitidos
Regras de roteamento, passos da jornada, marcos, conteúdo e metas de evento por bairro podem ser editados por unidade sem afetar as outras: a versão local sobrepõe a global (se a unidade tiver ao menos uma regra própria, as globais deixam de valer para ela).

## 4. Acompanhamento
`/admin/unidades` compara as unidades (cadastros, jornada, 7 dias, igreja, cestas, empregos, eventos, mantenedores). Os números vêm do relatório de impacto, atualizado de madrugada.

## Fora do Brasil
`units.locale = 'en'` usa `messages/en.json`. Ajustes necessários antes de operar em outro país: formato de telefone (hoje a normalização assume +55 quando o número vem sem código), formato de endereço, base legal equivalente à LGPD e preços da Meta na região.
