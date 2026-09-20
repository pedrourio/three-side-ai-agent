# ADR 0004 — O código propaga invalidação; o agente julga o que fazer

- Status: aceito
- Data: 2026-09-19

## Contexto

O caso mais interessante do projeto é o efeito cruzado: P pede outro horário
depois que S2 já reservou. Alguém precisa perceber que a reserva de S2 deixou de
valer. Se for o agente, ele pode simplesmente esquecer — e esquecer
silenciosamente é o pior desfecho possível, porque parece que funcionou. Se for
o código, o agente deixa de ter o problema interessante para resolver.

## Decisão

Dividir por natureza da tarefa:

- **Contabilidade é do código.** Quando um fato muda de valor ou é invalidado,
  todo fato que declara depender dele volta a `precisa_reconfirmar` e suas
  confirmações caem. As dependências são declaradas no cenário.
- **Julgamento é do agente.** Quem avisar primeiro, se cancela com S2 antes de
  oferecer alternativa a P, se negocia, se desiste.

## Consequências

- O agente não pode perder uma confirmação sem que o painel mostre.
- O comportamento interessante — ordem, tato, negociação — continua sendo dele.
- Os testes afirmam sobre a propagação sem precisar de LLM real.
- Custo: as dependências entre fatos precisam ser declaradas corretamente no
  cenário; cenário mal declarado produz propagação errada.

## Alternativas descartadas

- **Agente decide tudo, inclusive o que invalidar** — mais desafiador, mas o
  modo de falha é invisível e o projeto perde a capacidade de dizer se o agente
  acertou.
- **Código decide tudo, inclusive a reação** — vira a FSM rejeitada no ADR 0002.
