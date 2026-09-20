# Feature 05 — Segundo cenário: negociação de entrega

## Objetivo

Um segundo cenário de domínio completamente distinto do médico —
comprador (C), fornecedor (F) e transportadora (T) negociando uma entrega — sem
alterar uma linha de `src/core/`.

## Por que existe

Esta feature não entrega valor ao usuário; ela **testa uma afirmação de
arquitetura**. O [ADR 0002](../adr/0002-agente-unico-com-estado-compartilhado.md)
e a decisão de cenário como dado (spec §6) afirmam que o núcleo não conhece o
domínio. A forma honesta de verificar isso é trocar o domínio inteiro e ver o
que quebra.

Por isso ela vem **por último**, e não antes: rodada cedo, passa trivialmente
porque ainda não há domínio embutido para vazar.

## Escopo

- `scenarios/delivery-negotiation.yaml` com três canais, fatos e dependências
  próprias (ex.: `quantity` → `price` → `pickup_window` → `carrier_booking`).
- Seletor de cenário na tela já existe desde o épico 04; nenhuma mudança de UI.

## Critério de pronto

- O cenário roda de ponta a ponta pela tela sem que `src/core/` tenha mudado.
- Se `src/core/` **precisou** mudar, a mudança é registrada: qual suposição do
  domínio médico tinha vazado, e um ADR se a correção alterou o desenho.
- `git diff --stat` do commit desta feature é a evidência, em qualquer um dos
  dois casos.
