# three-side-ai-agent

Um agente de IA que conversa simultaneamente com três pessoas — cada uma com
parte da informação, nenhuma falando com as outras — para completar um objetivo
único. O desafio é coordenar estado sob efeitos cruzados, não conversar.

Desenho completo: @docs/superpowers/specs/2026-09-19-three-side-ai-agent-design.md
Decisões e seus porquês: @docs/adr/README.md
Backlog: @docs/features/README.md

## Comandos

- `make test` — testes determinísticos, sem rede nem chave de API. Sempre rode
  antes de dizer que terminou.
- `make lint` — estilo (ruff) + fronteira de import (import-linter).
- `make up` / `make down` / `make logs` — Compose (postgres, litellm, api).
- `make ping` — confere que o gateway de LLM responde com um modelo real.
- `make test-db` — testes que exigem Postgres (a partir da tarefa 02-08).
- `make types` — gera os tipos TypeScript a partir dos modelos Pydantic (a
  partir do épico 03).

## Regras de fronteira

- `src/core/` NÃO importa `src/api/`, `fastapi` nem `uvicorn`. É o que mantém o
  agente testável sem servidor. `make lint` falha se você quebrar.
- `ModelPort` é síncrono e bloqueia por chamada; o épico 03 roda o worker com
  `asyncio.to_thread`.
- Tipos TypeScript de contrato do backend são **gerados**, nunca escritos à mão.
- Teste que precise de LLM real leva `@pytest.mark.live`; teste que precise de
  Postgres leva `@pytest.mark.db`. Nenhum dos dois entra no `make test`.

## Convenções

- **Todo o código em inglês**: arquivos, funções, variáveis, nomes de tool,
  valores de status, chaves de cenário, nomes de evento. Em português apenas o
  texto que uma pessoa lê (interface e descrições de papel nos cenários) e a
  documentação.
- Documentação, ADRs, backlog e mensagens de commit em português.

## Fluxo de trabalho

- TDD: teste que falha → rodar e ver falhar → implementação mínima → rodar e ver
  passar → commit.
- Uma tarefa do backlog por vez; os passos do arquivo da tarefa são o roteiro.
- Decisão cara de reverter vira ADR antes do código (`/adr`). ADRs são imutáveis:
  um ADR errado se supersede, não se reescreve. Decisão barata é sua, tome e siga.
