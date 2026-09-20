# Épico 01 — Fundação

## Objetivo

Um repositório que sobe com um comando e se testa com outro, antes de existir
qualquer agente. Tudo que vem depois depende de `make test` ser rápido, offline
e verde.

## Por que existe

A estratégia de teste inteira (spec §8) depende de duas coisas que precisam
estar de pé desde o primeiro dia: a fronteira `core/` ↔ `api/` verificada por
ferramenta ([ADR 0008](../../adr/0008-nucleo-independente-de-framework-web.md)),
e o gateway de LLM como container separado
([ADR 0005](../../adr/0005-litellm-como-gateway-multi-provedor.md)). Retroajustar
qualquer uma das duas depois custa caro.

## Tarefas

1. [Esqueleto Python que se testa e se linta](01-esqueleto-python.md)
2. [Compose com LiteLLM respondendo](02-compose-com-litellm.md)
3. [Setup versionável do Claude](03-setup-do-claude.md)

## Critério de pronto

- `make test` roda em segundos, sem rede e sem chave de API, e passa.
- `make lint` falha se alguém importar `fastapi` dentro de `src/core/`.
- `make up` sobe `postgres`, `litellm` e `api`; `make ping` obtém uma resposta de
  um modelo gratuito real através do proxy.
- `CLAUDE.md` e `.claude/` commitados; `/adr` cria ADR numerado.
