# ADR 0007 — Uma fila serializada por sessão

- Status: aceito
- Data: 2026-09-19

## Contexto

Três pessoas digitam ao mesmo tempo e timers vencem no meio. Sem ordenação, dois
ciclos podem ler e escrever o mesmo quadro de fatos simultaneamente e produzir
estado corrompido — e, pior, corrompido de forma não reproduzível.

## Decisão

Cada sessão tem uma `asyncio.Queue` e **um único worker**. Mensagens dos três
canais e eventos de timer entram todos na mesma fila; o agente processa um
evento por vez.

## Consequências

- Impossível haver dois ciclos concorrentes sobre o mesmo estado; nenhum lock
  necessário.
- A demo fica reproduzível: a ordem dos eventos é explícita e registrada na
  trilha.
- O agente nunca processa duas coisas em paralelo — irrelevante para três
  interlocutores humanos digitando.
- Custo: não escala para múltiplos workers. A fila é o ponto de troca no dia em
  que isso importar.

## Alternativas descartadas

- **Processamento paralelo com lock sobre o estado** — mais rápido no papel, mas
  introduz contenção e ordem não determinística sem ganho perceptível nesta
  escala.
- **Uma fila por canal** — recria o problema: três filas concorrendo pelo mesmo
  quadro de fatos.
