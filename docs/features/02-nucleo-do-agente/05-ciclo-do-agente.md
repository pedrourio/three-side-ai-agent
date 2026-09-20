# Tarefa 02-05 — O ciclo: laço autônomo, trilha e recuperação de erro

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §5.3 (o tick), §5.5 (falhas), §5.6 (trilha)
**ADRs:** [0002](../../adr/0002-agente-unico-com-estado-compartilhado.md),
[0003](../../adr/0003-laco-autonomo-com-auto-cessao-e-teto.md)

**Entregável verificável:** com um modelo falso roteirizado, o agente processa
uma mensagem de S1, fala com S2 e P no mesmo ciclo, continua sozinho enquanto
declarar `keep_working`, para no quinto ciclo consecutivo sem humano, e grava
uma trilha que explica cada passo.

## Contexto para quem implementa

Aqui as peças anteriores viram agente. Três comportamentos precisam sair certos,
e cada um tem um teste que é praticamente uma cláusula de contrato:

**Autonomia com freio.** O agente roda de novo sozinho se chamou `keep_working`.
O contador de ciclos autônomos zera quando um humano fala e estoura em 5
([ADR 0003](../../adr/0003-laco-autonomo-com-auto-cessao-e-teto.md)). Estourar
não mata a sessão: marca `stalled`, que a tela pinta de vermelho.

**Recuperação de erro sem apagar o que deu certo.** As tool calls de uma resposta
são aplicadas em ordem. Na primeira que falhar, o resto daquela resposta é
descartado e o erro volta ao modelo como mensagem de correção. São no máximo
**duas chamadas de modelo por ciclo**; se a segunda também falhar, o ciclo aborta
e o aborto vira evento na trilha. As calls que já tinham sido aplicadas
permanecem — elas eram válidas, e desfazê-las exigiria transação sobre o quadro
de fatos sem ganho real.

**Trilha completa.** Um `CycleRecord` por ciclo, sempre — inclusive nos ciclos
que abortaram. Sem isso o painel não tem o que mostrar e o projeto perde metade
do seu propósito.

## Arquivos

- Criar: `src/core/state.py`
- Criar: `src/core/prompt.py`
- Criar: `src/core/cycle.py`
- Criar: `tests/core/test_cycle.py`

## Interfaces

- Consome: `Scenario` (02-01), `FactsBoard`/`Fact`/`FactChange` (02-02),
  `ModelPort`/`ModelReply`/`ToolCall`/`ModelError` (02-03), `Clock` (02-03),
  tools e efeitos (02-04).
- Produz:
  - `Message(channel, author, text, at)` com `author: Literal["human", "agent"]`
  - `Followup(id, due_at, reason)`
  - `SessionStatus` (`StrEnum`): `SLEEPING`, `STALLED`, `FINISHED`
  - `Trigger(kind, channel, detail)` com
    `kind: Literal["human_message", "followup", "self_continue"]`
  - `CycleRecord(index, at, trigger, reasoning, tool_calls, errors, fact_changes, kept_working)`
  - `SessionState(scenario_id, messages, facts, followups, autonomous_cycles, status, outcome, cycles)`
  - `build_messages(scenario, state, trigger, errors=()) -> list[dict]`
  - `MAX_AUTONOMOUS_CYCLES = 5`
  - `Agent(scenario, model, clock=SystemClock(), max_autonomous_cycles=...,
    on_cycle=None, should_stop=None)` com `handle(state, trigger) -> SessionState`
    e `start() -> SessionState` (estado inicial vazio do cenário)

`on_cycle(state, record)` e `should_stop()` são opcionais e existem por um motivo
específico: sem eles, os cinco ciclos autônomos só aparecem na tela numa rajada
no fim, e o "botão de parar o agente" do spec §7.1 não tem onde se pendurar.
Custam seis linhas agora; depois, com o épico 03 em cima, custam reescrever o
laço. `ModelPort` é **síncrono** e bloqueia por chamada — o épico 03 roda
`await asyncio.to_thread(agent.handle, ...)`.

## Passos

- [ ] **Passo 1: implementar `src/core/state.py`**

Não há TDD aqui: é declaração de dados, exercitada pelos testes do ciclo.

```python
from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field

from core.facts import Fact, FactChange
from core.llm import ToolCall


class Message(BaseModel):
    channel: str
    author: Literal["human", "agent"]
    text: str
    at: datetime


class Followup(BaseModel):
    id: str
    due_at: datetime
    reason: str


class SessionStatus(StrEnum):
    SLEEPING = "sleeping"
    STALLED = "stalled"
    FINISHED = "finished"
    ERROR = "error"
    STOPPED = "stopped"  # parada manual; a tela distingue do teto estourado


class Trigger(BaseModel):
    kind: Literal["human_message", "followup", "self_continue"]
    channel: str | None = None
    detail: str = ""
    followup_id: str | None = None


class CycleRecord(BaseModel):
    index: int
    at: datetime
    trigger: Trigger
    reasoning: str
    tool_calls: list[ToolCall] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    fact_changes: list[FactChange] = Field(default_factory=list)
    kept_working: bool = False


class SessionState(BaseModel):
    scenario_id: str
    messages: list[Message] = Field(default_factory=list)
    facts: dict[str, Fact] = Field(default_factory=dict)
    followups: list[Followup] = Field(default_factory=list)
    autonomous_cycles: int = 0
    status: SessionStatus = SessionStatus.SLEEPING
    outcome: str | None = None
    cycles: list[CycleRecord] = Field(default_factory=list)

    def channel_messages(self, channel: str) -> list[Message]:
        return [message for message in self.messages if message.channel == channel]
```

- [ ] **Passo 2: escrever os testes do ciclo, que devem falhar**

`tests/core/test_cycle.py`:

```python
from datetime import UTC, datetime

import pytest

from core.cycle import MAX_AUTONOMOUS_CYCLES, Agent
from core.facts import FactStatus
from core.llm import ModelReply, ToolCall
from core.scenario import Channel, FactSpec, Scenario
from core.state import SessionStatus, Trigger
from core.testing import FakeClock, FakeModel

SCENARIO = Scenario(
    id="t",
    name="Teste",
    goal="Combinar um horário entre os três.",
    channels=[
        Channel(id="s1", label="S1", role="Pede o agendamento."),
        Channel(id="s2", label="S2", role="Conhece a agenda."),
        Channel(id="p", label="P", role="Aceita ou recusa."),
    ],
    facts=[
        FactSpec(name="slot", source=["s2"], confirmation=["p", "s1"]),
        FactSpec(name="booking", source=["s2"], confirmation=["s2"], depends_on=["slot"]),
    ],
)


def reply(*calls: ToolCall, reasoning: str = "") -> ModelReply:
    return ModelReply(reasoning=reasoning, tool_calls=list(calls))


def send(channel: str, text: str = "...") -> ToolCall:
    return ToolCall(name="send", arguments={"channel": channel, "text": text})


def keep_working(reason: str = "ainda falta") -> ToolCall:
    return ToolCall(name="keep_working", arguments={"reason": reason})


def agent(*replies: ModelReply) -> tuple[Agent, FakeModel, FakeClock]:
    model = FakeModel(list(replies))
    clock = FakeClock(datetime(2026, 1, 1, 12, 0, tzinfo=UTC))
    return Agent(SCENARIO, model, clock=clock), model, clock


def human(channel: str = "s1", text: str = "preciso agendar") -> Trigger:
    return Trigger(kind="human_message", channel=channel, detail=text)


def test_agent_can_speak_to_several_channels_in_one_cycle():
    engine, _, _ = agent(reply(send("s2", "Tem horário?"), send("p", "Você prefere manhã?")))
    state = engine.start()

    state = engine.handle(state, human())

    agent_messages = [m for m in state.messages if m.author == "agent"]
    assert [m.channel for m in agent_messages] == ["s2", "p"]


def test_human_message_is_recorded_before_the_agent_thinks():
    engine, model, _ = agent(reply())
    state = engine.handle(engine.start(), human("s1", "preciso agendar o João"))

    assert state.messages[0].author == "human"
    assert state.messages[0].text == "preciso agendar o João"
    assert "preciso agendar o João" in str(model.calls[0])


def test_agent_sleeps_when_it_does_not_ask_to_continue():
    engine, _, _ = agent(reply(send("s2")))
    state = engine.handle(engine.start(), human())

    assert state.status is SessionStatus.SLEEPING
    assert len(state.cycles) == 1


def test_agent_runs_again_while_it_keeps_working():
    engine, _, _ = agent(
        reply(send("s2"), keep_working()),
        reply(send("p"), keep_working()),
        reply(send("s1")),
    )
    state = engine.handle(engine.start(), human())

    assert len(state.cycles) == 3
    assert [c.trigger.kind for c in state.cycles] == [
        "human_message",
        "self_continue",
        "self_continue",
    ]
    assert state.status is SessionStatus.SLEEPING


def test_the_cap_stops_a_runaway_agent():
    engine, _, _ = agent(*[reply(keep_working()) for _ in range(20)])
    state = engine.handle(engine.start(), human())

    assert len(state.cycles) == MAX_AUTONOMOUS_CYCLES + 1  # o do humano + 5 autônomos
    assert state.status is SessionStatus.STALLED


def test_a_human_message_resets_the_cap():
    engine, _, _ = agent(*[reply(keep_working()) for _ in range(20)])
    state = engine.handle(engine.start(), human())
    assert state.status is SessionStatus.STALLED

    state = engine.handle(state, human("p", "oi"))

    assert state.autonomous_cycles == MAX_AUTONOMOUS_CYCLES
    assert len(state.cycles) == 2 * (MAX_AUTONOMOUS_CYCLES + 1)


def test_finish_ends_the_session():
    engine, _, _ = agent(
        reply(ToolCall(name="finish", arguments={"outcome": "agendado para 14h"}))
    )
    state = engine.handle(engine.start(), human())

    assert state.status is SessionStatus.FINISHED
    assert state.outcome == "agendado para 14h"


def test_a_tool_error_is_sent_back_to_the_model_and_the_retry_is_applied():
    bad = ToolCall(name="send", arguments={"channel": "s9", "text": "oi"})
    engine, model, _ = agent(reply(bad), reply(send("s2", "corrigido")))

    state = engine.handle(engine.start(), human())

    assert len(model.calls) == 2, "o modelo foi chamado de novo com o erro"
    assert "s9" in str(model.calls[1])
    assert [m.text for m in state.messages if m.author == "agent"] == ["corrigido"]
    assert state.cycles[0].errors and "s9" in state.cycles[0].errors[0]


def test_two_failures_abort_the_cycle_without_killing_the_session():
    bad = ToolCall(name="teleport", arguments={})
    engine, model, _ = agent(reply(bad), reply(bad))

    state = engine.handle(engine.start(), human())

    assert len(model.calls) == 2
    assert state.status is SessionStatus.SLEEPING, "sessão continua viva"
    assert state.cycles[0].errors[-1].startswith("ciclo abortado")


def test_calls_applied_before_an_error_are_kept():
    engine, _, _ = agent(
        reply(
            ToolCall(name="record_fact", arguments={"name": "slot", "value": "14h", "source": "s2"}),
            ToolCall(name="confirm_fact", arguments={"name": "slot", "channel": "s2"}),
            send("p", "nunca enviada"),
        ),
        reply(),
    )
    state = engine.handle(engine.start(), human())

    assert state.facts["slot"].value == "14h", "a call válida antes do erro valeu"
    assert [m.text for m in state.messages if m.author == "agent"] == []


def test_a_dead_provider_marks_the_session_as_error_without_losing_the_trail():
    """Spec §5.5: se nenhum provedor atender, a sessão fica visivelmente em erro."""

    class DeadModel:
        def complete(self, messages, tools):
            from core.llm import ModelError

            raise ModelError("todos os provedores recusaram")

    engine = Agent(SCENARIO, DeadModel(), clock=FakeClock(datetime(2026, 1, 1, tzinfo=UTC)))
    state = engine.handle(engine.start(), human())

    assert state.status is SessionStatus.ERROR
    assert "provedor" in state.cycles[0].errors[0]


def test_a_new_human_message_revives_a_session_in_error():
    class FlakyModel:
        def __init__(self):
            self.calls = 0

        def complete(self, messages, tools):
            from core.llm import ModelError

            self.calls += 1
            if self.calls == 1:
                raise ModelError("cota estourada")
            return reply(send("s2", "voltei"))

    engine = Agent(SCENARIO, FlakyModel(), clock=FakeClock(datetime(2026, 1, 1, tzinfo=UTC)))
    state = engine.handle(engine.start(), human())
    assert state.status is SessionStatus.ERROR

    state = engine.handle(state, human("s1", "e aí?"))

    assert state.status is SessionStatus.SLEEPING


def test_the_hooks_let_the_caller_watch_and_stop():
    seen = []
    engine, _, _ = agent(*[reply(keep_working()) for _ in range(20)])
    engine = Agent(
        SCENARIO,
        FakeModel([reply(send("s2"), keep_working()) for _ in range(20)]),
        clock=FakeClock(datetime(2026, 1, 1, tzinfo=UTC)),
        on_cycle=lambda state, record: seen.append(record.index),
        should_stop=lambda: len(seen) >= 2,
    )

    state = engine.handle(engine.start(), human())

    assert seen == [0, 1], "o chamador viu cada ciclo antes de handle retornar"
    assert state.status is SessionStatus.STOPPED


def test_the_trail_records_the_fact_diff():
    engine, _, _ = agent(
        reply(
            ToolCall(name="record_fact", arguments={"name": "slot", "value": "14h", "source": "s2"}),
            reasoning="S2 ofereceu as 14h.",
        )
    )
    state = engine.handle(engine.start(), human())

    record = state.cycles[0]
    assert record.reasoning == "S2 ofereceu as 14h."
    assert record.fact_changes[0].fact == "slot"
    assert record.fact_changes[0].after.status is FactStatus.PROPOSED


def test_state_survives_a_round_trip_through_json():
    engine, _, _ = agent(reply(send("s2")))
    state = engine.handle(engine.start(), human())

    from core.state import SessionState

    assert SessionState.model_validate_json(state.model_dump_json()) == state
```

- [ ] **Passo 3: rodar e ver falhar**

Run: `uv run pytest tests/core/test_cycle.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.cycle'`.

- [ ] **Passo 4: implementar `src/core/prompt.py`**

O prompt é conteúdo em português: as três personas conversam em português.

```python
from __future__ import annotations

from core.facts import Fact
from core.scenario import Scenario
from core.state import SessionState, Trigger

SYSTEM = """\
Você é um agente que conversa ao mesmo tempo com {count} pessoas diferentes, \
em conversas separadas. Elas NÃO se falam. Só você enxerga o quadro completo.

Objetivo: {goal}

Canais:
{channels}

Regras:
- Você só fala com alguém chamando a tool `send`. Texto fora de tool não chega
  a ninguém; use-o apenas para registrar seu raciocínio.
- Registre no quadro de fatos tudo que for combinado, usando `record_fact` e
  `confirm_fact`. O quadro é a memória confiável; a conversa não é.
- Quando um fato muda, as confirmações dos fatos que dependem dele caem
  sozinhas. Repare nisso e resolva com as pessoas certas.
- Se ainda tem trabalho a fazer sem depender de resposta de ninguém, chame
  `keep_working`. Se está esperando alguém, não chame: você dorme até falarem.
- Nunca invente uma confirmação que não recebeu.
"""


def build_messages(
    scenario: Scenario,
    state: SessionState,
    trigger: Trigger,
    errors: tuple[str, ...] = (),
) -> list[dict]:
    channels = "\n".join(f"- {c.id} ({c.label}): {c.role.strip()}" for c in scenario.channels)
    system = SYSTEM.format(count=len(scenario.channels), goal=scenario.goal.strip(), channels=channels)

    parts = [_facts_block(scenario, state.facts), _conversations_block(scenario, state)]
    if state.followups:
        pending = "\n".join(f"- {f.id} vence {f.due_at:%H:%M}: {f.reason}" for f in state.followups)
        parts.append(f"Lembretes pendentes:\n{pending}")
    parts.append(_trigger_block(trigger))

    messages = [{"role": "system", "content": system}, {"role": "user", "content": "\n\n".join(parts)}]

    if errors:
        listed = "\n".join(f"- {error}" for error in errors)
        messages.append(
            {
                "role": "user",
                "content": (
                    f"Suas chamadas anteriores falharam:\n{listed}\n"
                    "Corrija e chame as tools de novo. As chamadas que deram certo antes do "
                    "erro já foram aplicadas; não as repita."
                ),
            }
        )

    return messages


def _facts_block(scenario: Scenario, facts: dict[str, Fact]) -> str:
    lines = []
    for spec in scenario.facts:
        fact = facts.get(spec.name)
        value = "—" if fact is None or fact.value is None else fact.value
        status = "—" if fact is None else fact.status.value
        confirmed = "ninguém" if fact is None or not fact.confirmed_by else ", ".join(fact.confirmed_by)
        needs = ", ".join(spec.confirmation) or "ninguém"
        lines.append(
            f"- {spec.name}: {value} | status {status} | confirmado por {confirmed} "
            f"| precisa de {needs}"
        )
    return "Quadro de fatos:\n" + "\n".join(lines)


def _conversations_block(scenario: Scenario, state: SessionState) -> str:
    blocks = []
    for channel in scenario.channels:
        history = state.channel_messages(channel.id)
        body = (
            "\n".join(f"  {'você' if m.author == 'agent' else channel.id}: {m.text}" for m in history)
            or "  (ainda não conversaram)"
        )
        blocks.append(f"Conversa com {channel.id} ({channel.label}):\n{body}")
    return "\n\n".join(blocks)


def _trigger_block(trigger: Trigger) -> str:
    match trigger.kind:
        case "human_message":
            return f"Acabou de chegar mensagem de {trigger.channel}. Decida o que fazer."
        case "followup":
            return f"Um lembrete seu venceu: {trigger.detail}. Decida o que fazer."
        case _:
            return f"Você mesmo pediu para continuar: {trigger.detail}. Siga."
```

- [ ] **Passo 5: implementar `src/core/cycle.py`**

```python
from __future__ import annotations

from collections.abc import Callable

from core.clock import Clock, SystemClock
from core.facts import FactsBoard
from core.llm import ModelError, ModelPort, ModelReply, ToolCall
from core.prompt import build_messages
from core.scenario import Scenario
from core.state import CycleRecord, Followup, Message, SessionState, SessionStatus, Trigger
from core.tools import (
    Finished,
    FollowupCancelled,
    FollowupScheduled,
    KeepWorking,
    OutgoingMessage,
    ToolError,
    ToolResult,
    apply_tool_call,
    tool_schemas,
)

MAX_AUTONOMOUS_CYCLES = 5
MAX_MODEL_CALLS_PER_CYCLE = 2


class Agent:
    def __init__(
        self,
        scenario: Scenario,
        model: ModelPort,
        clock: Clock | None = None,
        max_autonomous_cycles: int = MAX_AUTONOMOUS_CYCLES,
        new_id: Callable[[], str] | None = None,
        on_cycle: Callable[[SessionState, CycleRecord], None] | None = None,
        should_stop: Callable[[], bool] | None = None,
    ) -> None:
        self._scenario = scenario
        self._model = model
        self._clock = clock or SystemClock()
        self._cap = max_autonomous_cycles
        self._new_id = new_id
        self._on_cycle = on_cycle
        self._should_stop = should_stop

    def start(self) -> SessionState:
        board = FactsBoard(self._scenario)
        return SessionState(scenario_id=self._scenario.id, facts=board.snapshot())

    def handle(self, state: SessionState, trigger: Trigger) -> SessionState:
        state = state.model_copy(deep=True)

        if trigger.kind == "human_message":
            state.autonomous_cycles = 0
            if state.status is SessionStatus.ERROR:
                state.status = SessionStatus.SLEEPING
            state.messages.append(
                Message(
                    channel=trigger.channel or "",
                    author="human",
                    text=trigger.detail,
                    at=self._clock.now(),
                )
            )

        settled = (SessionStatus.FINISHED, SessionStatus.ERROR)

        while True:
            kept_working = self._run_one_cycle(state, trigger)

            if state.status in settled or not kept_working:
                if state.status not in settled:
                    state.status = SessionStatus.SLEEPING
                return state

            if self._should_stop is not None and self._should_stop():
                state.status = SessionStatus.STOPPED
                return state

            if state.autonomous_cycles >= self._cap:
                state.status = SessionStatus.STALLED
                return state

            state.autonomous_cycles += 1
            trigger = Trigger(kind="self_continue", detail=kept_working)

    def _run_one_cycle(self, state: SessionState, trigger: Trigger) -> str | None:
        board = FactsBoard.from_snapshot(self._scenario, state.facts)
        schemas = tool_schemas(self._scenario)

        record = CycleRecord(
            index=len(state.cycles), at=self._clock.now(), trigger=trigger, reasoning=""
        )
        keep_working_reason: str | None = None
        errors: list[str] = []

        for attempt in range(MAX_MODEL_CALLS_PER_CYCLE):
            messages = build_messages(self._scenario, state, trigger, tuple(errors))
            try:
                reply: ModelReply = self._model.complete(messages, schemas)
            except ModelError as error:
                record.errors.append(f"nenhum provedor atendeu: {error}")
                state.status = SessionStatus.ERROR
                break
            record.reasoning = reply.reasoning or record.reasoning
            record.tool_calls.extend(reply.tool_calls)

            failed = False
            for call in reply.tool_calls:
                try:
                    result = self._apply(call, board)
                except ToolError as error:
                    errors.append(f"{call.name}: {error}")
                    record.errors.append(f"{call.name}: {error}")
                    failed = True
                    break

                record.fact_changes.extend(result.fact_changes)
                keep_working_reason = self._apply_effects(result, state) or keep_working_reason

            state.facts = board.snapshot()

            if not failed:
                break
            if attempt == MAX_MODEL_CALLS_PER_CYCLE - 1:
                record.errors.append("ciclo abortado após duas tentativas")

        record.kept_working = keep_working_reason is not None
        state.cycles.append(record)
        if self._on_cycle is not None:
            self._on_cycle(state, record)
        return keep_working_reason

    def _apply(self, call: ToolCall, board: FactsBoard) -> ToolResult:
        kwargs = {} if self._new_id is None else {"new_id": self._new_id}
        return apply_tool_call(
            call, scenario=self._scenario, board=board, clock=self._clock, **kwargs
        )

    def _apply_effects(self, result: ToolResult, state: SessionState) -> str | None:
        keep_working_reason = None
        for effect in result.effects:
            match effect:
                case OutgoingMessage(channel=channel, text=text):
                    state.messages.append(
                        Message(channel=channel, author="agent", text=text, at=self._clock.now())
                    )
                case FollowupScheduled(id=identifier, due_at=due_at, reason=reason):
                    state.followups = [f for f in state.followups if f.id != identifier]
                    state.followups.append(Followup(id=identifier, due_at=due_at, reason=reason))
                case FollowupCancelled(id=identifier):
                    state.followups = [f for f in state.followups if f.id != identifier]
                case Finished(outcome=outcome):
                    state.status = SessionStatus.FINISHED
                    state.outcome = outcome
                case KeepWorking(reason=reason):
                    keep_working_reason = reason
        return keep_working_reason
```

- [ ] **Passo 6: rodar e ver passar**

Run: `uv run pytest tests/core/test_cycle.py -v`
Esperado: PASS, quinze testes.

Se `test_the_cap_stops_a_runaway_agent` contar errado, revise a ordem: o ciclo
disparado pelo humano não conta como autônomo; os cinco seguintes contam.

- [ ] **Passo 7: rodar tudo e commitar**

```bash
make test && make lint
git add src/core/state.py src/core/prompt.py src/core/cycle.py tests/core/test_cycle.py
git commit -m "feat: ciclo do agente com laço autônomo, teto, recuperação de erro e trilha"
```

## Pronto quando

- Os quinze testes passam, offline.
- `SessionState` faz round-trip por JSON sem perder nada — é pré-requisito da
  persistência (tarefa 02-07) e do WebSocket (épico 03).
- Nenhum teste deste arquivo faz chamada de rede.
