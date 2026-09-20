# Notas da revisão

Dois revisores leram o backlog antes de a implementação começar; um deles rodou
o código das tarefas. O que era bug ou armadilha já foi corrigido nas tarefas. O
que sobrou está aqui: são decisões suas, para tomar quando passar pelo arquivo.
Nenhuma precisa de ADR, nenhuma precisa ser resolvida agora.

## Buracos de contabilidade (02-01, 02-02, 02-05)

Todos produzem o mesmo tipo de silêncio que o ADR 0004 quer evitar — o painel
fica verde sobre algo que não é verdade:

- `Scenario` sem `extra="forbid"`: um YAML com `dependson:` em vez de
  `depends_on:` carrega calado, e a propagação simplesmente nunca acontece.
- `confirm` num fato sem valor devolve `CONFIRMED` com `value=None`.
- `handle` não checa status na entrada: sessão `finished` continua trabalhando
  se alguém mandar mensagem.
- `from_snapshot` estoura `KeyError` se o cenário ganhou um fato desde a última
  sessão; a CLI não compara `state.scenario_id` com `scenario.id`, então reabrir
  `--session demo` apontando para outro YAML roda com os fatos errados.

## Ganchos que os épicos 03 e 04 vão pedir

Aditivos, nenhum força reescrita se for feito quando o consumidor aparecer:

- `list_scenarios(directory)` em `scenario.py` — o REST precisa enumerar, e sem
  isso o `glob` acaba do lado errado da fronteira.
- `list_sessions() -> list[SessionSummary]` no store — `list_ids()` obriga a tela
  a carregar cada sessão inteira para montar o seletor. É um
  `SELECT id, state->>'scenario_id', state->>'status', updated_at`, exatamente o
  que o JSONB do ADR 0009 comprou.
- `next_due_at(state)` em `followups.py` — transforma o timer do épico 03 em um
  `asyncio.sleep` em vez de polling.
- O épico 03 precisa de quatro coisas que hoje não estão escritas nele: a task
  de timer que enfileira os follow-ups vencidos (hoje só o `/tick` manual da CLI
  os dispara), o save pelo `SessionStore` a cada evento, um evento `snapshot` na
  conexão do WebSocket (senão a tela não tem de onde se desenhar após um F5), e
  os payloads tipados dos eventos.

## Infra que vai irritar

- `compose.yaml` monta `./src` mas o uvicorn sobe sem `--reload`: editar código
  não muda nada no container.
- O `CMD ["uv", "run", "--no-dev", ...]` do Dockerfile tenta sincronizar no
  start, enquanto o build usou `--no-install-project`. `UV_FROZEN=1` e
  `--no-sync` resolvem.
- Rode `make fmt` antes do primeiro `make lint`: o código colado nas tarefas tem
  linhas longas e um import não usado.

## Pequenos

- Nada impede um teste de `make test` abrir socket. Uma fixture `autouse` em
  `tests/conftest.py` que faz `socket.socket.connect` levantar `RuntimeError`,
  pulada quando o teste tem marcador `live` ou `db`, resolve. (Não pega psycopg,
  que conecta pelo libpq em C — mas cobre LLM, HTTP e WebSocket, que é o risco.)
- `prompt_chars: int` no `CycleRecord` custa uma linha e dá dado para decidir o
  resumo por canal quando o prompt começar a inchar (risco da spec §13).
- O spec §5.2 ainda documenta `schedule_followup(when, ...)` e não menciona
  `keep_working`; o backlog implementa `in_minutes` e a oitava tool. O código
  está certo, o spec é que envelheceu.
- O critério de sucesso §2 nomeia dois rompimentos; o roteiro da 02-07 só cobre
  "P pede outro horário". Vale rodar "S1 cancela tudo" também.
