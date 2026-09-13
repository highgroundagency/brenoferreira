# Teste manual da fila de reenvio (Fase 1)

1. No celular, abrir o app instalado e logar como evangelista; deixar a tela "Nova pessoa" aberta.
2. Ativar o modo avião. Preencher e confirmar um cadastro → deve aparecer "Salvo no aparelho — envia quando houver sinal" e o banner com a contagem pendente.
3. Repetir mais um cadastro offline (2 pendentes).
4. Desativar o modo avião → em até alguns segundos o banner some e aparece "2 cadastro(s) enviado(s)". Conferir em "Meus cadastros" e no painel da central.
5. Reabrir o app com rede e sem pendências: nenhuma mensagem duplicada (idempotência por `client_uuid`).
6. Caso de erro de regra (ex.: bairro fora da unidade): o item fica na fila com `last_error` — revisar pelo DevTools → IndexedDB `transtornar` → `pending_registrations`.
