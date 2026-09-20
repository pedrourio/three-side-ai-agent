# Épico 03 — Transporte

## Objetivo

Expor o núcleo pela web sem que o núcleo saiba disso: sessões com fila
serializada, REST mínimo e um WebSocket por sessão com eventos tipados, cujos
tipos TypeScript são gerados, nunca escritos à mão.

## Por que existe

A serialização por sessão
([ADR 0007](../../adr/0007-fila-serializada-por-sessao.md)) é o que impede dois
ciclos concorrentes de corromperem o quadro de fatos quando três pessoas digitam
ao mesmo tempo. E é aqui que a fronteira do
[ADR 0008](../../adr/0008-nucleo-independente-de-framework-web.md) é exercida na
prática: `api/` importa `core/`, jamais o contrário.

## Tarefas previstas

Detalhadas quando o épico 02 fechar.

1. Sessões: `asyncio.Queue` + um único worker, com teste de ordenação sob
   mensagens concorrentes dos três canais
2. REST: criar sessão, listar sessões, listar cenários
3. WebSocket: eventos `human_message` entrando; `agent_message`,
   `facts_changed`, `cycle`, `status` saindo
4. `make types`: JSON Schema dos modelos Pydantic → TypeScript

## Critério de pronto

- Duas mensagens enviadas simultaneamente por canais diferentes produzem dois
  ciclos ordenados, nunca ciclos concorrentes — com teste que prova.
- Um cliente de teste conecta no WebSocket, envia mensagem e recebe a sequência
  completa de eventos.
- `make types` gera os tipos do front e `make lint` falha se estiverem
  desatualizados em relação aos modelos Pydantic.
