# Tarefa 02-07 — Persistência e CLI de terminal

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §4 (persistência), §8 (o núcleo roda sem servidor)
**ADRs:** [0006](../../adr/0006-sqlite-com-checkpointer-langgraph.md),
[0008](../../adr/0008-nucleo-independente-de-framework-web.md)

**Entregável verificável:** você conduz um agendamento inteiro pelo terminal,
contra um modelo real, fecha a CLI, reabre com o mesmo id de sessão e continua de
onde parou.

## Decisão pendente — resolva antes do passo 2

O [ADR 0006](../../adr/0006-sqlite-com-checkpointer-langgraph.md) decidiu
persistir "via checkpointer do LangGraph", quando o desenho do ciclo ainda era
uma incógnita. O ciclo que saiu da tarefa 02-05 é um laço Python simples: ele
não tem nós, nem ramificação condicional, nem estado de grafo. Usar LangGraph
agora significaria envolver uma função em um `StateGraph` de um nó só para ter
acesso ao `SqliteSaver` — peso morto disfarçado de arquitetura.

**Não implemente nenhuma das duas opções antes de registrar um ADR.** Rode
`/adr persistência da sessão` e decida entre:

- **A — SQLite direto.** ~40 linhas guardando `SessionState` serializado em
  JSON. Remove a dependência do LangGraph do projeto inteiro e supersede o
  ADR 0006. Custo: se um dia o agente virar orquestrador + sub-agentes
  ([ADR 0002](../../adr/0002-agente-unico-com-estado-compartilhado.md), alternativa
  descartada), LangGraph volta a fazer sentido e essa camada é reescrita.
- **B — LangGraph com `SqliteSaver`.** Honra o ADR 0006 e a stack escolhida no
  início. Custo: uma dependência grande e uma indireção que hoje não paga por si.

Os passos abaixo assumem **A**, que é a recomendação; se o ADR escolher **B**,
troque o passo 3 pela montagem do `StateGraph` mantendo a mesma interface
`SessionStore`, e o resto da tarefa vale igual.

## Arquivos

- Criar: `src/core/store.py`
- Criar: `src/core/cli.py`
- Criar: `tests/core/test_store.py`
- Modificar: `docs/adr/` (ADR novo, superseando ou confirmando o 0006)

## Interfaces

- Consome: `SessionState` (02-05), `Agent` (02-05), `due_followups`/`trigger_for`
  (02-06), `load_scenario` (02-01), `LiteLLMModel` (02-03).
- Produz:
  - `SessionStore` (Protocol): `load(session_id) -> SessionState | None`,
    `save(session_id, state) -> None`, `list_ids() -> list[str]`
  - `SqliteSessionStore(path: Path)` implementando `SessionStore`
  - `python -m core.cli <caminho-do-cenário> [--session ID]`

## Passos

- [ ] **Passo 1: registrar o ADR da decisão acima**

```
/adr persistência da sessão
```

- [ ] **Passo 2: escrever os testes do store, que devem falhar**

`tests/core/test_store.py`:

```python
from datetime import UTC, datetime

from core.state import Message, SessionState, SessionStatus
from core.store import SqliteSessionStore


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


def test_unknown_session_is_none(tmp_path):
    store = SqliteSessionStore(tmp_path / "s.sqlite")

    assert store.load("nope") is None


def test_saved_state_comes_back_identical(tmp_path):
    store = SqliteSessionStore(tmp_path / "s.sqlite")
    state = a_state()

    store.save("demo", state)

    assert store.load("demo") == state


def test_saving_again_overwrites(tmp_path):
    store = SqliteSessionStore(tmp_path / "s.sqlite")
    store.save("demo", a_state())

    updated = a_state()
    updated.status = SessionStatus.FINISHED
    store.save("demo", updated)

    assert store.load("demo").status is SessionStatus.FINISHED


def test_state_survives_a_new_connection(tmp_path):
    path = tmp_path / "s.sqlite"
    SqliteSessionStore(path).save("demo", a_state())

    assert SqliteSessionStore(path).load("demo") == a_state()


def test_lists_sessions(tmp_path):
    store = SqliteSessionStore(tmp_path / "s.sqlite")
    store.save("b", a_state())
    store.save("a", a_state())

    assert store.list_ids() == ["a", "b"]
```

- [ ] **Passo 3: rodar, ver falhar, e implementar `src/core/store.py`**

Run: `uv run pytest tests/core/test_store.py -v` → FAIL, módulo inexistente.

```python
from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Protocol

from core.state import SessionState

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    state TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
)
"""


class SessionStore(Protocol):
    def load(self, session_id: str) -> SessionState | None: ...
    def save(self, session_id: str, state: SessionState) -> None: ...
    def list_ids(self) -> list[str]: ...


class SqliteSessionStore:
    def __init__(self, path: Path) -> None:
        self._path = Path(path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute(SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self._path, isolation_level=None)

    def load(self, session_id: str) -> SessionState | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT state FROM sessions WHERE id = ?", (session_id,)
            ).fetchone()
        return SessionState.model_validate_json(row[0]) if row else None

    def save(self, session_id: str, state: SessionState) -> None:
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO sessions (id, state, updated_at) "
                "VALUES (?, ?, datetime('now')) "
                "ON CONFLICT(id) DO UPDATE SET state = excluded.state, "
                "updated_at = excluded.updated_at",
                (session_id, state.model_dump_json()),
            )

    def list_ids(self) -> list[str]:
        with self._connect() as connection:
            return [row[0] for row in connection.execute("SELECT id FROM sessions ORDER BY id")]
```

Run: `uv run pytest tests/core/test_store.py -v` → PASS, cinco testes.

- [ ] **Passo 4: implementar `src/core/cli.py`**

A CLI não tem teste automatizado: ela é um cliente fino sobre peças já testadas,
e testá-la seria testar `input()`. O que ela prova é outra coisa — que o núcleo
roda sem servidor, e que ele funciona contra um modelo de verdade.

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
from core.store import SqliteSessionStore

HELP = """\
Comandos:
  <canal>: <texto>   fala como aquela pessoa (ex: s1: preciso agendar o João)
  /facts             mostra o quadro de fatos
  /trail             mostra a trilha de ciclos
  /tick              dispara follow-ups vencidos
  /quit              sai (a sessão fica salva)
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Conduz uma sessão pelo terminal.")
    parser.add_argument("scenario", type=Path)
    parser.add_argument("--session", default="demo")
    parser.add_argument("--db", type=Path, default=Path("data/sessions.sqlite"))
    args = parser.parse_args()

    scenario = load_scenario(args.scenario)
    store = SqliteSessionStore(args.db)
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
    print(f"Sessão '{args.session}' salva em {args.db}.")


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

- [ ] **Passo 5: conduzir uma sessão de verdade**

```bash
make up
LLM_BASE_URL=http://localhost:4000 uv run python -m core.cli \
  scenarios/appointment-scheduling.yaml --session demo
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

- [ ] **Passo 6: commit**

```bash
make test && make lint
git add src/core/store.py src/core/cli.py tests/core/test_store.py docs/adr
git commit -m "feat: persistência em SQLite e CLI de terminal para conduzir sessões"
```

## Pronto quando

- Os cinco testes do store passam.
- O roteiro do passo 5 roda inteiro contra um modelo gratuito real.
- Reabrir a sessão restaura conversas, fatos, follow-ups e trilha.
- Existe um ADR novo decidindo a questão da persistência, e o ADR 0006 está
  coerente com ele — confirmado ou marcado como superado.
