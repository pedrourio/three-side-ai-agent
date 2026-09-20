# Backlog

Spec que origina este backlog:
[`docs/superpowers/specs/2026-09-19-three-side-ai-agent-design.md`](../superpowers/specs/2026-09-19-three-side-ai-agent-design.md).
Decisões que o sustentam: [`docs/adr/`](../adr/README.md).

## Como este backlog funciona

- **Uma tarefa = um entregável verificável de ponta a ponta.** Não existe tarefa
  "criar o model X"; existe "carregar cenário com validação, com teste que falha
  se o YAML estiver quebrado".
- Cada arquivo de tarefa é **autocontido**: quem for implementar não precisa ter
  participado da conversa que gerou o spec. Traz caminhos exatos de arquivo, as
  interfaces que consome e produz, e os passos de TDD.
- **Épico** = subpasta com um markdown do épico (objetivo, ordem, critério de
  pronto) e um markdown por tarefa. Feature solta = markdown na raiz desta pasta.
- Ordem dos passos dentro de uma tarefa: teste que falha → rodar e ver falhar →
  implementação mínima → rodar e ver passar → commit.

Achados da revisão que não viraram correção nas tarefas estão em
[NOTAS-DA-REVISAO.md](NOTAS-DA-REVISAO.md) — decisões suas, na hora que passar
por cada arquivo.

## Ordem de execução

| # | Épico / feature | Entrega |
|---|-----------------|---------|
| 01 | [Fundação](01-fundacao/EPICO.md) | repositório que sobe e se testa sozinho |
| 02 | [Núcleo do agente](02-nucleo-do-agente/EPICO.md) | agente coordenando três canais, dirigível por terminal |
| 03 | [Transporte](03-transporte/EPICO.md) | sessões, fila serializada e WebSocket tipado |
| 04 | [Tela](04-tela/EPICO.md) | três chats + painel de estado e trilha |
| 05 | [Segundo cenário](05-segundo-cenario.md) | prova de que o domínio não vazou para o núcleo |

Os épicos 03 e 04 e a feature 05 estão detalhados em nível de épico. As tarefas
de cada um são escritas quando o épico anterior fecha — detalhar a tela antes do
núcleo existir produz ficção que se reescreve.

## Restrições globais

Valem para toda tarefa, sem repetição em cada arquivo.

- **Python 3.12+**, gerenciado por `uv`. Lint e format por `ruff`. Fronteira de
  import por `import-linter`. Tipos por **Pydantic v2**.
- **Todo o código em inglês, sem exceção** — arquivos, módulos, funções,
  variáveis, nomes de tool expostos ao modelo, valores de status, chaves de
  cenário, nomes de evento. Em português apenas: rótulos e mensagens da
  interface, descrições de papel dentro dos cenários (conteúdo de prompt), e a
  documentação.
- **`src/core/` não importa `src/api/`, `fastapi` nem `uvicorn`.** Verificado por
  `make lint`, não por disciplina.
- **`make test` roda sem rede e sem chave de API**, em segundos. Teste que
  precise de LLM real vive marcado `@pytest.mark.live`; teste que precise de
  Postgres vive marcado `@pytest.mark.db` e roda por `make test-db`. Nenhum dos
  dois entra no `make test`.
- **Nenhum tipo TypeScript escrito à mão** para contratos do backend: são
  gerados por `make types`.
- **Decisão arquitetural vira ADR antes do código.**
- Commits pequenos e frequentes, um por passo de commit descrito na tarefa.
