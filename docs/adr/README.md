# Decisões arquiteturais

Formato MADR enxuto. Numeração sequencial, atribuída na criação. ADRs são
imutáveis: um ADR errado não se apaga nem se reescreve — cria-se um novo que o
supersede.

| # | Decisão | Status |
|---|---------|--------|
| [0001](0001-usar-adrs-para-decisoes-arquiteturais.md) | Usar ADRs para decisões arquiteturais | aceito |
| [0002](0002-agente-unico-com-estado-compartilhado.md) | Um agente único com estado compartilhado | aceito |
| [0003](0003-laco-autonomo-com-auto-cessao-e-teto.md) | Laço autônomo com auto-cessão e teto de ciclos | aceito |
| [0004](0004-codigo-propaga-invalidacao-agente-julga.md) | O código propaga invalidação; o agente julga | aceito |
| [0005](0005-litellm-como-gateway-multi-provedor.md) | LiteLLM Proxy como gateway multi-provedor | aceito |
| [0006](0006-sqlite-com-checkpointer-langgraph.md) | SQLite em volume com o checkpointer do LangGraph | superado por 0009 |
| [0007](0007-fila-serializada-por-sessao.md) | Uma fila serializada por sessão | aceito |
| [0008](0008-nucleo-independente-de-framework-web.md) | O núcleo não conhece framework web nem provedor | aceito |
| [0009](0009-postgres-como-banco-da-sessao.md) | Postgres como banco da sessão | aceito |
