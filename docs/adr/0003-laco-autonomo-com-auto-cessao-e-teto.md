# ADR 0003 — Laço autônomo com auto-cessão e teto de ciclos

- Status: aceito
- Data: 2026-09-19

## Contexto

Se o agente só reage a mensagens recebidas, ele nunca age por iniciativa
própria, e metade do desafio desaparece: decidir sozinho que precisa falar com
S2 antes que alguém peça. Por outro lado, um laço verdadeiramente contínuo
chamando o LLM sem parar queima cota e é difícil de conter numa demo.

## Decisão

O agente acorda por três motivos: mensagem nova, timer vencido, ou ele mesmo ter
declarado **continuar** ao fim do ciclo anterior.

Freios:

- teto de **5 ciclos consecutivos sem entrada humana**, que o força a dormir;
- o estouro do teto é visível no painel e deixa a sessão marcada como travada,
  nunca encerrada em silêncio;
- botão de parada manual na UI.

## Consequências

- Autonomia real: o agente inicia contato e faz follow-up sem ninguém pedir.
- Consumo limitado e previsível por rodada.
- Laço infinito vira sintoma observável em vez de conta de API surpresa.
- Custo: o comportamento deixa de ser puramente determinístico em relação à
  entrada humana; os testes usam relógio falso e modelo falso para recuperar o
  determinismo.

## Alternativas descartadas

- **Só reagir a mensagens** — determinístico e simples, mas mata a iniciativa
  própria.
- **Tick fixo a cada N segundos** — simples, mas gasta chamada de LLM mesmo
  quando nada mudou.
- **Laço livre com só um botão de pausa** — máxima liberdade para observar
  comportamento emergente, risco alto de queimar cota de provedor gratuito.
