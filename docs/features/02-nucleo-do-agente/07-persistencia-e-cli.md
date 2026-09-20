# Tarefa 02-07 — Persistência em Postgres e CLI de terminal

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §4 (persistência), §8 (o núcleo roda sem servidor)
**ADRs:** [0009](../../adr/0009-postgres-como-banco-da-sessao.md),
[0008](../../adr/0008-nucleo-independente-de-framework-web.md)

**Entregável verificável:** você conduz um agendamento inteiro pelo terminal,
contra um modelo real, fecha a CLI, reabre com o mesmo id de sessão e continua de
onde parou — e consegue perguntar em SQL quais sessões estouraram o teto de
ciclos.

## Decisão pendente — resolva antes do passo 2

O [ADR 0009](../../adr/0009-postgres-como-banco-da-sessao.md) definiu Postgres
com uma tabela atrás do Protocol `SessionStore`. Ao fazer isso, ele tirou do
LangGraph a única função que lhe restava neste desenho: o checkpointer.

O ciclo que saiu da tarefa 02-05 é um laço Python simples — sem nós, sem
ramificação condicional, sem estado de grafo. Com a persistência resolvida por
SQL direto, **o LangGraph deixa de ter papel algum no projeto**.

**Não implemente antes de registrar um ADR.** Rode `/adr papel do LangGraph no
projeto` e decida entre:

- **A — Remover o LangGraph da stack.** Uma dependência grande a menos e nenhuma
  indireção. Recomendado: nada no desenho atual o usa. Custo: se o agente um dia
  virar orquestrador + sub-agentes (a alternativa descartada no
  [ADR 0002](../../adr/0002-agente-unico-com-estado-compartilhado.md)), ele volta
  a fazer sentido e a decisão se supersede.
- **B — Manter e reescrever o ciclo como `StateGraph`.** Nós `think` → `act` →
  `decide`, com aresta condicional voltando para `think` no `keep_working`, e
  `PostgresSaver` no lugar do `SessionStore`. Só vale se o objetivo de
  aprendizado do projeto incluir LangGraph explicitamente — o que é uma razão
  legítima, mas precisa estar escrita no ADR, e não deduzida do silêncio.

Os passos abaixo assumem **A**. Se o ADR escolher **B**, a tarefa vira reescrever
`cycle.py` como grafo mantendo os catorze testes de 02-05 passando sem alteração
— esse é o critério que prova que a troca foi de mecanismo, não de comportamento.

## Arquivos

- Criar: `src/core/store.py`
- Criar: `src/core/cli.py`
- Modificar: `src/core/testing.py` (`InMemorySessionStore`)
- Criar: `tests/db/test_store.py`
- Modificar: `Makefile` (alvo `test-db`)
- Modificar: `docs/adr/` (ADR novo sobre o LangGraph)

## Interfaces

- Consome: `SessionState` (02-05), `Agent` (02-05), `due_followups`/`trigger_for`
  (02-06), `load_scenario` (02-01), `LiteLLMModel` (02-03).
- Produz:
  - `SessionStore` (Protocol): `load(session_id) -> SessionState | None`,
    `save(session_id, state) -> None`, `list_ids() -> list[str]`
  - `PostgresSessionStore(dsn: str)` implementando `SessionStore`
  - `core.testing.InMemorySessionStore()` implementando `SessionStore`
  - `python -m core.cli <caminho-do-cenário> [--session ID]`

## Passos

- [ ] **Passo 1: registrar o ADR da decisão acima**

```
/adr papel do LangGraph no projeto
```

Se a decisão for **A**, remova a dependência: `uv remove langgraph` (se já tiver
sido adicionada em alguma tarefa anterior) e confira que nada em `src/` a
importa.

- [ ] **Passo 2: escrever os testes do store, que devem falhar**

`tests/db/test_store.py`. Note o `pytestmark`: estes testes **não** rodam no
`make test`; eles exigem o Compose de pé, por decisão do
[ADR 0009](../../adr/0009-postgres-como-banco-da-sessao.md).

```python
import os
from datetime import UTC, datetime

import psycopg
import pytest

from core.state import Message, SessionState, SessionStatus
from core.store import PostgresSessionStore

pytestmark = pytest.mark.db

DSN = os.environ.get("DATABASE_URL", "postgresql://agent:agent@localhost:5432/agent")


@pytest.fixture
def store() -> PostgresSessionStore:
    instance = PostgresSessionStore(DSN)
    with psycopg.connect(DSN, autocommit=True) as connection:
        connection.execute("TRUNCATE sessions")
    return instance


def a_state() -> SessionState:
    return SessionState(
        scenario_id="t",
        messages=[
            Message(
                channel="s1",
                author="human",
                text="preciso agendar",
                at=datetime(2026, 1, 1, tzinfo=UTC),
            )
        ],
        status=SessionStatus.SLEEPING,
    )


def test_unknown_session_is_none(store):
    assert store.load("nope") is None


def test_saved_state_comes_back_identical(store):
    state = a_state()

    store.save("demo", state)

    assert store.load("demo") == state


def test_saving_again_overwrites(store):
    store.save("demo", a_state())

    updated = a_state()
    updated.status = SessionStatus.FINISHED
    store.save("demo", updated)

    assert store.load("demo").status is SessionStatus.FINISHED
    assert store.list_ids() == ["demo"], "atualizar não cria uma segunda linha"


def test_state_survives_a_new_connection(store):
    store.save("demo", a_state())

    assert PostgresSessionStore(DSN).load("demo") == a_state()


def test_lists_sessions(store):
    store.save("b", a_state())
    store.save("a", a_state())

    assert store.list_ids() == ["a", "b"]


def test_the_trail_is_queryable_as_jsonb(store):
    """A razão de ser do ADR 0009: perguntar sobre o comportamento em SQL."""
    stalled = a_state()
    stalled.status = SessionStatus.STALLED
    store.save("travada", stalled)
    store.save("normal", a_state())

    with psycopg.connect(DSN, autocommit=True) as connection:
        rows = connection.execute(
            "SELECT id FROM sessions WHERE state->>'status' = 'stalled'"
        ).fetchall()

    assert [row[0] for row in rows] == ["travada"]
```

- [ ] **Passo 3: rodar e ver falhar**

```bash
make up
uv run pytest -m db -v
```

Esperado: FAIL — `ModuleNotFoundError: No module named 'core.store'`.

- [ ] **Passo 4: implementar `src/core/store.py`**

Uma conexão por operação, sem pool: a escala é uma escrita por ciclo de agente, e
pool aqui seria otimização sem medição.

```python
from __future__ import annotations

from typing import Protocol

from core.state import SessionState

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    state JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""

INDEX = "CREATE INDEX IF NOT EXISTS sessions_state_gin ON sessions USING GIN (state)"


class SessionStore(Protocol):
    def load(self, session_id: str) -> SessionState | None: ...
    def save(self, session_id: str, state: SessionState) -> None: ...
    def list_ids(self) -> list[str]: ...


class PostgresSessionStore:
    def __init__(self, dsn: str) -> None:
        self._dsn = dsn
        with self._connect() as connection:
            connection.execute(SCHEMA)
            connection.execute(INDEX)

    def _connect(self):
        import psycopg

        return psycopg.connect(self._dsn, autocommit=True)

    def load(self, session_id: str) -> SessionState | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT state::text FROM sessions WHERE id = %s", (session_id,)
            ).fetchone()
        return SessionState.model_validate_json(row[0]) if row else None

    def save(self, session_id: str, state: SessionState) -> None:
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO sessions (id, state, updated_at) "
                "VALUES (%s, %s::jsonb, now()) "
                "ON CONFLICT (id) DO UPDATE "
                "SET state = EXCLUDED.state, updated_at = EXCLUDED.updated_at",
                (session_id, state.model_dump_json()),
            )

    def list_ids(self) -> list[str]:
        with self._connect() as connection:
            return [
                row[0] for row in connection.execute("SELECT id FROM sessions ORDER BY id")
            ]
```

O import de `psycopg` fica dentro do método pelo mesmo motivo do `openai` em
`llm.py`: importar `core` não deve abrir driver de banco.

- [ ] **Passo 5: acrescentar o store em memória a `src/core/testing.py`**

É ele que mantém o `make test` offline quando o épico 03 precisar de um store.

```python
class InMemorySessionStore:
    """Store para o make test. Mesmo contrato do Postgres, sem servidor."""

    def __init__(self) -> None:
        self._states: dict[str, str] = {}

    def load(self, session_id: str):
        from core.state import SessionState

        raw = self._states.get(session_id)
        return SessionState.model_validate_json(raw) if raw else None

    def save(self, session_id: str, state) -> None:
        self._states[session_id] = state.model_dump_json()

    def list_ids(self) -> list[str]:
        return sorted(self._states)
```

Guardar JSON em vez do objeto é de propósito: assim o dublê cobra o mesmo
round-trip de serialização que o Postgres cobra, e um campo que não serializa
quebra no `make test`, não só na demo.

- [ ] **Passo 6: rodar e ver passar**

```bash
uv run pytest -m db -v
```

Esperado: PASS, seis testes.

- [ ] **Passo 7: acrescentar o alvo ao `Makefile`**

```makefile
test-db:  ## testes que exigem Postgres; precisa de make up antes
	uv run pytest -m db

.PHONY: help test test-db fmt lint up down logs ping
```

Confirme que `make test` **não** roda os testes `db`:

Run: `make test`
Esperado: a contagem de testes não inclui os seis do store.

- [ ] **Passo 8: implementar `src/core/cli.py`**

A CLI não tem teste automatizado: é um cliente fino sobre peças já testadas, e
testá-la seria testar `input()`. O que ela prova é outra coisa — que o núcleo
roda sem servidor, contra um modelo de verdade.

```python
"""Dirige uma sessão pelo terminal. Prova que o núcleo não precisa de servidor."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from core.clock import SystemClock
from core.cycle import Agent
from core.followups import due_followups, trigger_for
from core.llm import LiteLLMModel
from core.scenario import load_scenario
from core.state import SessionState, Trigger
from core.store import PostgresSessionStore

HELP = """\
Comandos:
  <canal>: <texto>   fala como aquela pessoa (ex: s1: preciso agendar o João)
  /facts             mostra o quadro de fatos
  /trail             mostra a trilha de ciclos
  /tick              dispara follow-ups vencidos
  /quit              sai (a sessão fica salva)
"""

DEFAULT_DSN = "postgresql://agent:agent@localhost:5432/agent"


def main() -> None:
    parser = argparse.ArgumentParser(description="Conduz uma sessão pelo terminal.")
    parser.add_argument("scenario", type=Path)
    parser.add_argument("--session", default="demo")
    parser.add_argument("--dsn", default=os.environ.get("DATABASE_URL", DEFAULT_DSN))
    args = parser.parse_args()

    scenario = load_scenario(args.scenario)
    store = PostgresSessionStore(args.dsn)
    model = LiteLLMModel(
        base_url=os.environ.get("LLM_BASE_URL", "http://localhost:4000"),
        model=os.environ.get("LLM_MODEL", "primary-agent"),
        api_key=os.environ.get("LLM_API_KEY", "sk-local-dev"),
    )
    agent = Agent(scenario, model, clock=SystemClock())

    state = store.load(args.session) or agent.start()
    print(f"Cenário: {scenario.name} | sessão: {args.session} | ciclos: {len(state.cycles)}")
    print(HELP)

    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            break

        if not line:
            continue
        if line == "/quit":
            break
        if line == "/facts":
            _print_facts(state)
            continue
        if line == "/trail":
            _print_trail(state)
            continue
        if line == "/tick":
            state = _fire_due(agent, state)
            store.save(args.session, state)
            continue

        channel, _, text = line.partition(":")
        channel = channel.strip()
        if channel not in scenario.channel_ids():
            print(f"canal desconhecido: '{channel}'. Use um de {sorted(scenario.channel_ids())}")
            continue

        before = len(state.messages)
        state = agent.handle(
            state, Trigger(kind="human_message", channel=channel, detail=text.strip())
        )
        store.save(args.session, state)
        _print_new_messages(state, before)
        print(f"[status: {state.status.value} | ciclos autônomos: {state.autonomous_cycles}]")

    store.save(args.session, state)
    print(f"Sessão '{args.session}' salva.")


def _fire_due(agent: Agent, state: SessionState) -> SessionState:
    pending = due_followups(state, SystemClock())
    if not pending:
        print("nenhum follow-up vencido")
        return state
    for followup in pending:
        print(f"[follow-up: {followup.reason}]")
        before = len(state.messages)
        state = agent.handle(state, trigger_for(followup))
        _print_new_messages(state, before)
    return state


def _print_new_messages(state: SessionState, before: int) -> None:
    for message in state.messages[before:]:
        if message.author == "agent":
            print(f"  agente → {message.channel}: {message.text}")


def _print_facts(state: SessionState) -> None:
    for fact in state.facts.values():
        confirmed = ", ".join(fact.confirmed_by) or "ninguém"
        print(f"  {fact.name}: {fact.value or '—'} [{fact.status.value}] confirmado por {confirmed}")


def _print_trail(state: SessionState) -> None:
    for record in state.cycles:
        calls = ", ".join(call.name for call in record.tool_calls) or "nada"
        print(f"  #{record.index} {record.trigger.kind}: {calls}")
        if record.reasoning:
            print(f"     pensou: {record.reasoning[:120]}")
        for error in record.errors:
            print(f"     ERRO: {error}")


if __name__ == "__main__":
    main()
```

- [ ] **Passo 9: conduzir uma sessão de verdade**

```bash
make up
uv run python -m core.cli scenarios/appointment-scheduling.yaml --session demo
```

Conduza o roteiro que define o épico:

1. `s1: preciso agendar cardiologia para o João, urgente`
2. responda como `s2` oferecendo um horário
3. confirme como `p`
4. `/facts` — confira que `slot` está `confirmed`
5. **`p: na verdade não consigo nesse horário, pode ser 16h?`**
6. `/facts` — `booking` deve estar `needs_reconfirmation`
7. `/trail` — a trilha deve explicar o que o agente fez e por quê
8. `/quit`, reabra com o mesmo `--session demo`, e confirme que tudo voltou

- [ ] **Passo 10: colher a primeira consulta analítica**

O que justifica o Postgres é poder perguntar isto:

```bash
psql "$DATABASE_URL" -c "
  SELECT id,
         state->>'status' AS status,
         jsonb_array_length(state->'cycles') AS ciclos
  FROM sessions
  ORDER BY updated_at DESC;
"
```

- [ ] **Passo 11: commit**

```bash
make test && make lint && make test-db
git add src/core/store.py src/core/cli.py src/core/testing.py tests/db Makefile docs/adr
git commit -m "feat: persistência em Postgres e CLI de terminal para conduzir sessões"
```

## Pronto quando

- Os seis testes de `make test-db` passam com o Compose de pé.
- `make test` continua offline, em segundos, e não inclui os testes `db`.
- O roteiro do passo 9 roda inteiro contra um modelo gratuito real.
- Reabrir a sessão restaura conversas, fatos, follow-ups e trilha.
- A consulta do passo 10 responde.
- Existe um ADR decidindo o papel do LangGraph, qualquer que seja a decisão.
