---
description: Cria o próximo ADR numerado no formato MADR enxuto
allowed-tools: Bash(ls:*), Read, Write, Edit
---

ADRs existentes:

!`ls docs/adr/ | grep -E '^[0-9]{4}-' | sort | tail -5`

Crie o **próximo** número sequencial de quatro dígitos, em
`docs/adr/NNNN-<slug-em-portugues>.md`, para a decisão: $ARGUMENTS

Formato:

- Título `# ADR NNNN — <decisão em uma frase afirmativa>`
- `- Status: aceito` e `- Data: <hoje, YYYY-MM-DD>`
- `## Contexto` — a pressão que força a escolha, não a escolha
- `## Decisão` — o que foi decidido, na voz ativa
- `## Consequências` — o que melhora e o que piora; sempre inclua o custo
- `## Alternativas descartadas` — cada uma com o motivo real da rejeição

Regras: ADRs são imutáveis. Se esta decisão substitui uma anterior, marque a
anterior como `superado por NNNN` e explique o que mudou desde então. Ao
terminar, adicione a linha correspondente na tabela de `docs/adr/README.md`.
