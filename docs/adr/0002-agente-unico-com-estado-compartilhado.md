# ADR 0002 — Um agente único com estado compartilhado

- Status: aceito
- Data: 2026-09-19

## Contexto

O agente conversa com três interlocutores que, juntos, perseguem um objetivo
único. É preciso decidir onde mora a inteligência de coordenação.

## Decisão

Um único grafo LangGraph. O estado carrega as três conversas **e** um quadro de
fatos estruturado (o que foi coletado, o que está confirmado por quem, o que
falta). A cada ciclo o agente enxerga tudo e age via tools.

## Consequências

- A coordenação é responsabilidade do agente — que é exatamente o que este
  projeto quer exercitar e observar.
- O estado é explícito e estruturado, então o painel tem o que mostrar e os
  testes têm o que afirmar.
- Uma única chamada de LLM por ciclo: barato e simples de depurar.
- Custo: o prompt cresce com as três conversas. Mitigação prevista é resumo por
  canal acima de um limiar.

## Alternativas descartadas

- **Orquestrador + um sub-agente por canal** — prompts menores e mais próximo de
  sistemas reais, mas triplica as chamadas e introduz o modo de falha mais
  traiçoeiro possível: coordenador e canal discordando sobre o estado. Passaria
  a depurar sincronização em vez de coordenação. Continua sendo a evolução
  natural se o prompt único sufocar.
- **Máquina de estados explícita com o LLM só redigindo texto** — robusto e
  barato, mas remove o desafio: quem coordena passa a ser a FSM escrita à mão, e
  conflitos viram `if` em vez de decisão do agente.
