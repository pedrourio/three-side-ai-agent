# Tarefa 02-04 — Tools do agente

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §5.2 (tools), §5.5 (falhas)
**ADRs:** [0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md)

**Entregável verificável:** cada tool call do modelo vira ou um efeito bem
definido, ou um `ToolError` com mensagem que o próprio modelo consegue usar para
se corrigir na segunda tentativa.

## Contexto para quem implementa

Este módulo é a única superfície pela qual o agente muda o mundo. Ele é
deliberadamente burro: valida, aplica no quadro de fatos, devolve efeitos. Não
decide nada — quem decide é o modelo, e quem executa os efeitos é o ciclo
(tarefa 02-05).

A mensagem de erro importa mais do que o normal aqui. Quando o modelo chama
`confirm_fact` com um canal errado, o texto do `ToolError` volta para ele como
mensagem de correção (spec §5.5: duas tentativas, depois aborta). "Canal
inválido" não ajuda; "canal 's2' não confirma o fato 'slot'; apenas ['p', 's1']"
ajuda.

## Arquivos

- Criar: `src/core/tools.py`
- Criar: `tests/core/test_tools.py`

## Interfaces

- Consome: `Scenario` (02-01), `FactsBoard`/`FactChange`/`FactError` (02-02),
  `ToolCall` (02-03), `Clock` (02-03).
- Produz:
  - efeitos: `OutgoingMessage(channel, text)`,
    `FollowupScheduled(id, due_at, reason)`, `FollowupCancelled(id)`,
    `Finished(outcome)`, `KeepWorking(reason)`
  - `Effect` (união dos acima)
  - `ToolResult(effects: list[Effect], fact_changes: list[FactChange])`
  - `ToolError(ValueError)`
  - `tool_schemas(scenario: Scenario) -> list[dict]` — schemas OpenAI, com os
    ids de canal e nomes de fato do cenário embutidos como `enum`
  - `apply_tool_call(call, *, scenario, board, clock, new_id=...) -> ToolResult`

## Por que os schemas são gerados a partir do cenário

Colocar `"enum": ["s1", "s2", "p"]` no schema faz o modelo errar menos canal do
que qualquer instrução em prosa, e é de graça — o cenário já tem a lista.

## Passos

- [ ] **Passo 1: escrever os testes, que devem falhar**

`tests/core/test_tools.py`:

```python
from datetime import UTC, datetime, timedelta

import pytest

from core.facts import FactsBoard, FactStatus
from core.llm import ToolCall
from core.scenario import Channel, FactSpec, Scenario
from core.testing import FakeClock
from core.tools import (
    Finished,
    FollowupCancelled,
    FollowupScheduled,
    KeepWorking,
    OutgoingMessage,
    ToolError,
    apply_tool_call,
    tool_schemas,
)

SCENARIO = Scenario(
    id="t",
    name="Teste",
    goal="Combinar.",
    channels=[
        Channel(id="s1", label="S1", role="Pede."),
        Channel(id="s2", label="S2", role="Agenda."),
        Channel(id="p", label="P", role="Aceita."),
    ],
    facts=[
        FactSpec(name="slot", source=["s2"], confirmation=["p", "s1"]),
        FactSpec(name="booking", source=["s2"], confirmation=["s2"], depends_on=["slot"]),
    ],
)


@pytest.fixture
def board():
    return FactsBoard(SCENARIO)


@pytest.fixture
def clock():
    return FakeClock(datetime(2026, 1, 1, 12, 0, tzinfo=UTC))


def call(tool, **arguments):
    return ToolCall(name=tool, arguments=arguments)


def apply(tool, board, clock, **arguments):
    return apply_tool_call(
        call(tool, **arguments),
        scenario=SCENARIO,
        board=board,
        clock=clock,
        new_id=lambda: "fixed-id",
    )


def test_send_produces_an_outgoing_message(board, clock):
    result = apply("send", board, clock, channel="s2", text="Tem horário?")

    assert result.effects == [OutgoingMessage(channel="s2", text="Tem horário?")]
    assert result.fact_changes == []


def test_send_to_an_unknown_channel_is_an_error(board, clock):
    with pytest.raises(ToolError, match="s9"):
        apply("send", board, clock, channel="s9", text="oi")


def test_record_fact_changes_the_board(board, clock):
    result = apply("record_fact", board, clock, name="slot", value="14h", source="s2")

    assert result.effects == []
    assert [change.fact for change in result.fact_changes] == ["slot"]
    assert board.snapshot()["slot"].value == "14h"


def test_confirm_fact_changes_the_board(board, clock):
    apply("record_fact", board, clock, name="slot", value="14h", source="s2")

    result = apply("confirm_fact", board, clock, name="slot", channel="p")

    assert board.snapshot()["slot"].confirmed_by == ["p"]
    assert result.fact_changes[0].reason == "p confirmou"


def test_invalidate_fact_propagates(board, clock):
    apply("record_fact", board, clock, name="slot", value="14h", source="s2")
    apply("record_fact", board, clock, name="booking", value="#1", source="s2")

    result = apply("invalidate_fact", board, clock, name="slot", reason="S1 cancelou")

    assert board.snapshot()["booking"].status is FactStatus.NEEDS_RECONFIRMATION
    assert {change.fact for change in result.fact_changes} == {"slot", "booking"}


def test_fact_errors_surface_as_tool_errors(board, clock):
    """FactError é erro de uso do agente; o ciclo o devolve ao modelo."""
    with pytest.raises(ToolError, match=r"apenas \['s2'\]"):
        apply("record_fact", board, clock, name="slot", value="14h", source="p")


def test_schedule_followup_uses_the_clock(board, clock):
    result = apply("schedule_followup", board, clock, in_minutes=10, reason="S2 calada")

    assert result.effects == [
        FollowupScheduled(
            id="fixed-id",
            due_at=datetime(2026, 1, 1, 12, 10, tzinfo=UTC),
            reason="S2 calada",
        )
    ]


def test_cancel_followup(board, clock):
    result = apply("cancel_followup", board, clock, id="fixed-id")

    assert result.effects == [FollowupCancelled(id="fixed-id")]


def test_finish_and_keep_working(board, clock):
    assert apply("finish", board, clock, outcome="agendado").effects == [
        Finished(outcome="agendado")
    ]
    assert apply("keep_working", board, clock, reason="falta avisar S1").effects == [
        KeepWorking(reason="falta avisar S1")
    ]


def test_unknown_tool_is_an_error(board, clock):
    with pytest.raises(ToolError, match="teleport"):
        apply("teleport", board, clock)


def test_missing_argument_is_an_error(board, clock):
    with pytest.raises(ToolError, match="text"):
        apply("send", board, clock, channel="s2")


def test_schemas_embed_the_scenario_vocabulary():
    schemas = {entry["function"]["name"]: entry["function"] for entry in tool_schemas(SCENARIO)}

    assert set(schemas) == {
        "send",
        "record_fact",
        "confirm_fact",
        "invalidate_fact",
        "schedule_followup",
        "cancel_followup",
        "finish",
        "keep_working",
    }
    assert schemas["send"]["parameters"]["properties"]["channel"]["enum"] == ["s1", "s2", "p"]
    assert schemas["record_fact"]["parameters"]["properties"]["name"]["enum"] == [
        "slot",
        "booking",
    ]


def test_clock_is_never_read_from_the_wall(board, clock):
    """Garante que o efeito usa o relógio injetado, não datetime.now()."""
    clock.advance(timedelta(hours=5))

    result = apply("schedule_followup", board, clock, in_minutes=1, reason="x")

    assert result.effects[0].due_at == datetime(2026, 1, 1, 17, 1, tzinfo=UTC)
```

- [ ] **Passo 2: rodar e ver falhar**

Run: `uv run pytest tests/core/test_tools.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.tools'`.

- [ ] **Passo 3: implementar `src/core/tools.py`**

```python
from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from pydantic import BaseModel, Field

from core.clock import Clock
from core.facts import FactChange, FactError, FactsBoard
from core.llm import ToolCall
from core.scenario import Scenario


class ToolError(ValueError):
    """Tool call inválida. A mensagem volta ao modelo como correção."""


class OutgoingMessage(BaseModel):
    channel: str
    text: str


class FollowupScheduled(BaseModel):
    id: str
    due_at: datetime
    reason: str


class FollowupCancelled(BaseModel):
    id: str


class Finished(BaseModel):
    outcome: str


class KeepWorking(BaseModel):
    reason: str


Effect = OutgoingMessage | FollowupScheduled | FollowupCancelled | Finished | KeepWorking


class ToolResult(BaseModel):
    effects: list[Effect] = Field(default_factory=list)
    fact_changes: list[FactChange] = Field(default_factory=list)


def tool_schemas(scenario: Scenario) -> list[dict]:
    channels = [channel.id for channel in scenario.channels]
    facts = [fact.name for fact in scenario.facts]

    def schema(name: str, description: str, properties: dict, required: list[str]) -> dict:
        return {
            "type": "function",
            "function": {
                "name": name,
                "description": description,
                "parameters": {
                    "type": "object",
                    "properties": properties,
                    "required": required,
                },
            },
        }

    channel = {"type": "string", "enum": channels}
    fact = {"type": "string", "enum": facts}

    return [
        schema(
            "send",
            "Envia uma mensagem para um dos canais. É a única forma de falar com alguém.",
            {"channel": channel, "text": {"type": "string"}},
            ["channel", "text"],
        ),
        schema(
            "record_fact",
            "Registra ou atualiza o valor de um fato, atribuindo-o a quem o informou.",
            {"name": fact, "value": {"type": "string"}, "source": channel},
            ["name", "value", "source"],
        ),
        schema(
            "confirm_fact",
            "Registra que um canal confirmou explicitamente um fato.",
            {"name": fact, "channel": channel},
            ["name", "channel"],
        ),
        schema(
            "invalidate_fact",
            "Marca um fato como inválido. Derruba as confirmações dos fatos que dependem dele.",
            {"name": fact, "reason": {"type": "string"}},
            ["name", "reason"],
        ),
        schema(
            "schedule_followup",
            "Agenda um lembrete para você mesmo, daqui a N minutos.",
            {"in_minutes": {"type": "integer", "minimum": 1}, "reason": {"type": "string"}},
            ["in_minutes", "reason"],
        ),
        schema(
            "cancel_followup",
            "Cancela um lembrete que você agendou e não é mais necessário.",
            {"id": {"type": "string"}},
            ["id"],
        ),
        schema(
            "finish",
            "Encerra a sessão. Use quando o objetivo foi atingido ou se tornou impossível.",
            {"outcome": {"type": "string"}},
            ["outcome"],
        ),
        schema(
            "keep_working",
            "Declara que você ainda tem trabalho a fazer e quer outro ciclo sem esperar "
            "resposta de ninguém. Sem esta chamada, você dorme até alguém falar.",
            {"reason": {"type": "string"}},
            ["reason"],
        ),
    ]


def apply_tool_call(
    call: ToolCall,
    *,
    scenario: Scenario,
    board: FactsBoard,
    clock: Clock,
    new_id: Callable[[], str] = lambda: uuid.uuid4().hex[:8],
) -> ToolResult:
    arguments = call.arguments

    def need(key: str) -> Any:
        if key not in arguments or arguments[key] in (None, ""):
            raise ToolError(f"'{call.name}' exige o argumento '{key}'")
        return arguments[key]

    def channel(key: str) -> str:
        value = need(key)
        if value not in scenario.channel_ids():
            raise ToolError(
                f"'{value}' não é um canal deste cenário; "
                f"use um de {sorted(scenario.channel_ids())}"
            )
        return value

    try:
        match call.name:
            case "send":
                return ToolResult(
                    effects=[OutgoingMessage(channel=channel("channel"), text=need("text"))]
                )
            case "record_fact":
                changes = board.record(need("name"), str(need("value")), channel("source"))
                return ToolResult(fact_changes=changes)
            case "confirm_fact":
                return ToolResult(fact_changes=board.confirm(need("name"), channel("channel")))
            case "invalidate_fact":
                return ToolResult(
                    fact_changes=board.invalidate(need("name"), str(need("reason")))
                )
            case "schedule_followup":
                minutes = int(need("in_minutes"))
                return ToolResult(
                    effects=[
                        FollowupScheduled(
                            id=new_id(),
                            due_at=clock.now() + timedelta(minutes=minutes),
                            reason=str(need("reason")),
                        )
                    ]
                )
            case "cancel_followup":
                return ToolResult(effects=[FollowupCancelled(id=str(need("id")))])
            case "finish":
                return ToolResult(effects=[Finished(outcome=str(need("outcome")))])
            case "keep_working":
                return ToolResult(effects=[KeepWorking(reason=str(need("reason")))])
            case _:
                raise ToolError(f"tool '{call.name}' não existe")
    except FactError as error:
        raise ToolError(str(error)) from error
    except (TypeError, ValueError) as error:
        if isinstance(error, ToolError):
            raise
        raise ToolError(f"'{call.name}': {error}") from error
```

- [ ] **Passo 4: rodar e ver passar**

Run: `uv run pytest tests/core/test_tools.py -v`
Esperado: PASS, treze testes.

- [ ] **Passo 5: commit**

```bash
git add src/core/tools.py tests/core/test_tools.py
git commit -m "feat: tools do agente com schemas derivados do cenário"
```

## Pronto quando

- Os treze testes passam.
- `tool_schemas` de um cenário diferente produz `enum` diferente, sem mudança de
  código — a verificação real disso é a feature 05.
- Toda mensagem de `ToolError` diz o que fazer, não só o que está errado.
