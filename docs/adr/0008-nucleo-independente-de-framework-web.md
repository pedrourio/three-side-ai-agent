# ADR 0008 — O núcleo não conhece framework web nem provedor

- Status: aceito
- Data: 2026-09-19

## Contexto

Um agente é não-determinístico, e um agente acoplado a WebSocket e a um provedor
de LLM é praticamente intestável: cada teste vira um teste de integração lento,
caro e instável.

## Decisão

`src/core/` é um pacote Python puro. Não importa `fastapi`, não conhece
WebSocket, e fala com o LLM através de uma interface mínima injetada.
`src/api/` depende de `core/`; nunca o contrário.

A regra é verificada por **import-linter** no `make lint`, não por disciplina.

## Consequências

- Os testes injetam um modelo falso com sequência roteirizada de tool calls, e
  passam a ser determinísticos, rápidos e sem chave de API.
- O agente roda por script de terminal, sem subir servidor.
- Personas simuladas por LLM (fase futura) plugam no núcleo sem tocar na web.
- Custo: uma indireção a mais entre agente e provedor.

## Alternativas descartadas

- **Núcleo dentro da aplicação FastAPI** — menos cerimônia no começo, mas
  qualquer teste exigiria cliente HTTP e servidor de pé.
- **Manter a regra só no CLAUDE.md** — uma regra sem verificação é uma
  recomendação; import-linter a torna real.
