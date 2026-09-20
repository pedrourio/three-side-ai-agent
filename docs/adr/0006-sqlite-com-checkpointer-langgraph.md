# ADR 0006 — SQLite em volume com o checkpointer do LangGraph

- Status: aceito
- Data: 2026-09-19

## Contexto

A sessão precisa sobreviver a um recarregamento de página, e a trilha de
decisões precisa continuar legível depois que a demo termina — é ela que
transforma "o agente errou" em "o agente errou aqui, por isto".

## Decisão

Persistir estado e trilha em SQLite, em volume do Compose, usando o checkpointer
do LangGraph.

## Consequências

- Recarregar a página continua a sessão de onde parou.
- Autópsia pós-demo é possível: a trilha está gravada.
- Zero infraestrutura adicional; o arquivo é copiável e inspecionável.
- Custo: um só processo escritor. Aceitável, porque a v1 já serializa por sessão
  (ADR 0007).

## Alternativas descartadas

- **Postgres** — necessário se houvesse concorrência real de escrita ou vários
  workers; hoje seria infraestrutura sem uso.
- **Só memória** — mais simples, mas perde a sessão a cada reload e apaga a
  trilha justamente quando ela seria útil.
