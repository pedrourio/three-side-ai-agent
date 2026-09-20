# ADR 0001 — Usar ADRs para decisões arquiteturais

- Status: aceito
- Data: 2026-09-19

## Contexto

O projeto é um desafio pessoal cujo valor está tanto no resultado quanto no
raciocínio que levou até ele. Decisões tomadas em conversa se perdem; três meses
depois ninguém lembra por que o agente é um só em vez de três, e a tentação de
refazer a escolha sem conhecer o motivo original é alta.

## Decisão

Toda decisão arquitetural é registrada como ADR em `docs/adr/`, no formato MADR
enxuto: contexto, decisão, consequências, alternativas descartadas.

Regras:

- numeração sequencial de quatro dígitos, atribuída na criação;
- ADRs são **imutáveis**: um ADR errado não se apaga nem se reescreve — cria-se
  um novo que o supersede, e o antigo passa a `status: superado por NNNN`;
- a decisão vem **antes** do código que a implementa;
- o comando `/adr` do Claude cria o próximo número no formato correto.

## Consequências

- Existe rastro de por que o sistema é como é, legível por quem não participou
  da conversa — inclusive por uma sessão futura do Claude.
- Custo: alguns minutos por decisão, e a disciplina de não pular a etapa quando
  a decisão parece óbvia no momento.

## Alternativas descartadas

- **Registrar só no spec** — o spec descreve o estado desejado, não a
  deliberação; ele é reescrito, e reescrever apaga o histórico.
- **Confiar no histórico do git** — mensagens de commit descrevem a mudança, não
  as alternativas rejeitadas nem o motivo.
