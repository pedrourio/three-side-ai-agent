# Épico 02 — Núcleo do agente

## Objetivo

O agente coordenando três canais, com quadro de fatos, propagação de
invalidação, laço autônomo, follow-ups e trilha — tudo rodando por terminal,
sem servidor web e sem LLM real nos testes.

## Por que existe

É o projeto. Todo o resto é entrega e observação. Este épico fecha quando você
consegue dirigir um agendamento inteiro pelo terminal, incluindo o caso que dá
nome ao desafio: P pede outro horário depois de S2 confirmar, e o agente
percebe.

ADRs que governam este épico:
[0002](../../adr/0002-agente-unico-com-estado-compartilhado.md) (um agente,
estado compartilhado), [0003](../../adr/0003-laco-autonomo-com-auto-cessao-e-teto.md)
(laço com freio), [0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md)
(código propaga, agente julga),
[0006](../../adr/0006-sqlite-com-checkpointer-langgraph.md) (persistência).

## Tarefas

1. [Cenário como dado, validado na carga](01-cenario-como-dado.md)
2. [Quadro de fatos e propagação de invalidação](02-quadro-de-fatos.md)
3. [Porta de LLM e modelo falso](03-porta-de-llm.md)
4. [Tools do agente](04-tools-do-agente.md)
5. [O ciclo: laço autônomo, trilha e recuperação de erro](05-ciclo-do-agente.md)
6. [Follow-ups com relógio injetável](06-followups.md)
7. [Persistência e CLI de terminal](07-persistencia-e-cli.md)

## Critério de pronto

- `python -m core.cli scenarios/appointment-scheduling.yaml` conduz uma sessão
  inteira pelo terminal contra um modelo real.
- Existe teste determinístico, sem rede, para: propagação de invalidação, teto
  de ciclos autônomos, follow-up vencendo com relógio falso, tool call
  malformada e cenário inválido.
- Reabrir a CLI com o mesmo id de sessão continua de onde parou.
