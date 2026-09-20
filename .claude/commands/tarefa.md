---
description: Carrega uma tarefa do backlog com todo o contexto para implementá-la
---

Implemente a tarefa do backlog em: $ARGUMENTS

Contexto obrigatório antes de escrever qualquer código:

- Leia o arquivo da tarefa por inteiro, incluindo "Interfaces" e "Pronto quando".
- Leia os ADRs que a tarefa referencia. Eles dizem por que o desenho é assim; se
  você discordar de um, pare e me diga — não implemente contra ele em silêncio.
- Restrições globais do backlog: @docs/features/README.md
- Achados de revisão ainda em aberto: @docs/features/NOTAS-DA-REVISAO.md

Siga os passos da tarefa na ordem. TDD de verdade: escreva o teste, rode e
**veja falhar** antes de implementar. Não pule o passo de ver falhar — teste que
nunca falhou não prova nada.

Ao final, rode `make test` e `make lint` e me mostre a saída antes de afirmar que
terminou.

Decisão técnica pequena é sua, tome e siga. Se for cara de reverter e a tarefa
não previu, pare e me avise: vira ADR antes do código.
