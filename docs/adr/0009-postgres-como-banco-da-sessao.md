# ADR 0009 — Postgres como banco da sessão

- Status: aceito
- Data: 2026-09-19
- Supersede: [0006](0006-sqlite-com-checkpointer-langgraph.md)

## Contexto

O [ADR 0006](0006-sqlite-com-checkpointer-langgraph.md) escolheu SQLite com o
argumento de que a v1 serializa por sessão
([ADR 0007](0007-fila-serializada-por-sessao.md)) e não tem concorrência de
escrita — então Postgres seria infraestrutura sem uso.

O argumento continua tecnicamente correto para a v1 e ainda assim a escolha
muda, por duas razões que o 0006 não pesou:

- **A trilha é dado de análise, não só de exibição.** O projeto existe para
  observar o comportamento do agente. Perguntas como "em quais sessões o teto de
  ciclos estourou?" ou "com que frequência uma confirmação caiu por propagação?"
  são o produto do projeto, e `JSONB` com índice GIN responde isso em SQL, sem
  carregar cada sessão em Python.
- **É o banco que o desenvolvedor usa de fato.** Este é um projeto de
  aprendizado; exercitar a ferramenta real vale mais do que economizar um
  container.

## Decisão

Postgres como banco da sessão, em container no Compose, com volume.

Uma tabela: `sessions(id TEXT PRIMARY KEY, state JSONB NOT NULL, updated_at
TIMESTAMPTZ)`. O acesso passa pelo Protocol `SessionStore`, implementado por
`PostgresSessionStore`.

Sem ferramenta de migração enquanto houver uma tabela: o schema é `CREATE TABLE
IF NOT EXISTS` idempotente na inicialização. Introduzir Alembic quando houver
duas tabelas ou a primeira alteração de coluna com dado em produção — o que
vier primeiro.

## Consequências

- A trilha é consultável por SQL, que é o que torna a observação do agente
  barata.
- O caminho para mais de um worker deixa de ter o banco como obstáculo.
- **Os testes do store deixam de caber no `make test`.** Eles passam a viver em
  `make test-db`, marcados `-m db`, e exigem o Compose de pé. O `make test`
  continua offline e em segundos usando `InMemorySessionStore` onde um store for
  necessário. O custo real: o SQL não é exercitado a cada `make test`, então
  quebrar o store só aparece em `make test-db` ou na demo.
- Mais um container e um `DATABASE_URL` para configurar.
- Escrever o estado inteiro a cada ciclo passa a ser uma escrita de rede em vez
  de um `write()` em arquivo local. Irrelevante nesta escala; vale registrar que
  a sessão é reescrita por completo, não em delta.

## Alternativas descartadas

- **SQLite** (a decisão do ADR 0006) — mais rápido nos testes e sem container,
  mas sem `JSONB` para analisar a trilha e sem o valor de aprendizado.
- **Postgres em produção e SQLite nos testes** — devolveria a velocidade ao
  `make test`, ao custo de testar um código e rodar outro. Rejeitado: é a classe
  de bug mais cara de diagnosticar, e o SQL do store é justamente a parte que
  difere entre os dois.
- **testcontainers dentro do `make test`** — SQL sempre exercitado, mas passaria
  a exigir Docker e download de imagem no comando que precisa ser o mais barato
  do projeto.
