# Tarefa 02-06 — Follow-ups com relógio injetável

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §5.3 (gatilhos), §6 (política de follow-up)
**ADRs:** [0003](../../adr/0003-laco-autonomo-com-auto-cessao-e-teto.md)

**Entregável verificável:** o agente fala com S2, ninguém responde, dez minutos
de relógio falso passam, e o agente acorda sozinho sabendo de quem está
esperando resposta — tudo sem `sleep()` e sem teste lento.

## Contexto para quem implementa

A tarefa 02-04 já deu ao agente a tool `schedule_followup`, com a qual ele agenda
lembretes por iniciativa própria. Esta tarefa adiciona a **rede de segurança
automática**: quando o agente manda mensagem para um canal, o sistema agenda
sozinho uma cobrança para `no_reply_minutes` depois, e cancela quando a pessoa
responde.

Por que automático e não só pelo agente: o modo de falha mais comum de um agente
conversacional é ficar esperando para sempre alguém que nunca vai responder. Um
modelo esperto agenda o próprio lembrete; um modelo fraco esquece. A política do
cenário garante o piso independentemente da qualidade do modelo.

Os dois mecanismos convivem: o automático usa ids `auto:<canal>`, o do agente usa
ids aleatórios. O agente pode cancelar o automático se achar que não faz sentido.

## Arquivos

- Criar: `src/core/followups.py`
- Modificar: `src/core/cycle.py` (agendamento automático e disparo)
- Criar: `tests/core/test_followups.py`

## Interfaces

- Consome: `SessionState`, `Followup`, `Trigger` (02-05), `Clock` (02-03),
  `Scenario.followup` (02-01).
- Produz:
  - `auto_followup_id(channel: str) -> str` → `f"auto:{channel}"`
  - `due_followups(state, clock) -> list[Followup]` — vencidos, mais antigo
    primeiro
  - `trigger_for(followup) -> Trigger` — `kind="followup"`
  - em `Agent`: agendamento automático após `send`, cancelamento ao receber
    mensagem humana do canal, e remoção do follow-up disparado ao tratar um
    `Trigger(kind="followup")`

## Passos

- [ ] **Passo 1: escrever os testes, que devem falhar**

`tests/core/test_followups.py`:

```python
from datetime import UTC, datetime, timedelta

from core.cycle import Agent
from core.followups import auto_followup_id, due_followups, trigger_for
from core.llm import ModelReply, ToolCall
from core.scenario import Channel, FactSpec, FollowupPolicy, Scenario
from core.state import Trigger
from core.testing import FakeClock, FakeModel

SCENARIO = Scenario(
    id="t",
    name="Teste",
    goal="Combinar.",
    channels=[
        Channel(id="s1", label="S1", role="Pede."),
        Channel(id="s2", label="S2", role="Agenda."),
    ],
    facts=[FactSpec(name="slot", source=["s2"], confirmation=["s1"])],
    followup=FollowupPolicy(no_reply_minutes=10),
)

START = datetime(2026, 1, 1, 12, 0, tzinfo=UTC)


def send(channel: str, text: str = "...") -> ToolCall:
    return ToolCall(name="send", arguments={"channel": channel, "text": text})


def build(*replies: ModelReply) -> tuple[Agent, FakeClock]:
    clock = FakeClock(START)
    return Agent(SCENARIO, FakeModel(list(replies)), clock=clock), clock


def test_sending_a_message_schedules_an_automatic_followup():
    engine, _ = build(ModelReply(tool_calls=[send("s2")]))

    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))

    followup = next(f for f in state.followups if f.id == auto_followup_id("s2"))
    assert followup.due_at == START + timedelta(minutes=10)
    assert "s2" in followup.reason


def test_a_reply_from_that_channel_cancels_the_automatic_followup():
    engine, _ = build(ModelReply(tool_calls=[send("s2")]), ModelReply())
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))

    state = engine.handle(
        state, Trigger(kind="human_message", channel="s2", detail="tenho às 14h")
    )

    assert auto_followup_id("s2") not in {f.id for f in state.followups}


def test_nothing_is_due_before_the_deadline():
    engine, clock = build(ModelReply(tool_calls=[send("s2")]))
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))

    clock.advance(timedelta(minutes=9))

    assert due_followups(state, clock) == []


def test_the_followup_is_due_after_the_deadline():
    engine, clock = build(ModelReply(tool_calls=[send("s2")]))
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))

    clock.advance(timedelta(minutes=10))
    due = due_followups(state, clock)

    assert [f.id for f in due] == [auto_followup_id("s2")]


def test_due_followups_come_oldest_first():
    engine, clock = build(ModelReply(tool_calls=[send("s1"), send("s2")]))
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))
    state.followups[0].due_at = START + timedelta(minutes=1)

    clock.advance(timedelta(hours=1))

    assert due_followups(state, clock)[0].due_at == START + timedelta(minutes=1)


def test_firing_a_followup_wakes_the_agent_and_consumes_it():
    engine, clock = build(
        ModelReply(tool_calls=[send("s2", "Tem horário?")]),
        ModelReply(tool_calls=[send("s2", "Oi, conseguiu ver?")]),
    )
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))
    clock.advance(timedelta(minutes=10))

    followup = due_followups(state, clock)[0]
    state = engine.handle(state, trigger_for(followup))

    assert state.cycles[-1].trigger.kind == "followup"
    assert [m.text for m in state.messages if m.author == "agent"][-1] == "Oi, conseguiu ver?"


def test_a_new_message_to_the_same_channel_pushes_the_deadline_forward():
    engine, clock = build(ModelReply(tool_calls=[send("s2")]), ModelReply(tool_calls=[send("s2")]))
    state = engine.handle(engine.start(), Trigger(kind="human_message", channel="s1", detail="oi"))

    clock.advance(timedelta(minutes=5))
    state = engine.handle(state, Trigger(kind="human_message", channel="s1", detail="e aí?"))

    followup = next(f for f in state.followups if f.id == auto_followup_id("s2"))
    assert followup.due_at == START + timedelta(minutes=15)
```

- [ ] **Passo 2: rodar e ver falhar**

Run: `uv run pytest tests/core/test_followups.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.followups'`.

- [ ] **Passo 3: implementar `src/core/followups.py`**

```python
from __future__ import annotations

from core.clock import Clock
from core.state import Followup, SessionState, Trigger


def auto_followup_id(channel: str) -> str:
    return f"auto:{channel}"


def due_followups(state: SessionState, clock: Clock) -> list[Followup]:
    now = clock.now()
    return sorted(
        (followup for followup in state.followups if followup.due_at <= now),
        key=lambda followup: followup.due_at,
    )


def trigger_for(followup: Followup) -> Trigger:
    return Trigger(kind="followup", detail=followup.reason, followup_id=followup.id)
```

- [ ] **Passo 4: ligar no ciclo**

Em `src/core/cycle.py`, importe os helpers:

```python
from datetime import timedelta

from core.followups import auto_followup_id
```

No começo de `handle`, ao registrar a mensagem humana, cancele a cobrança do
canal que respondeu, e ao tratar um follow-up, consuma o que disparou. **O patch
é aditivo** — as duas linhas que repõem o status de erro vêm de 02-05 e
continuam ali:

```python
        if trigger.kind == "human_message":
            state.autonomous_cycles = 0
            if state.status is SessionStatus.ERROR:   # vem de 02-05, não apague
                state.status = SessionStatus.SLEEPING
            channel = trigger.channel or ""
            state.followups = [f for f in state.followups if f.id != auto_followup_id(channel)]
            state.messages.append(
                Message(channel=channel, author="human", text=trigger.detail, at=self._clock.now())
            )
        elif trigger.kind == "followup":
            state.followups = [f for f in state.followups if f.id != trigger.followup_id]
```

Em `_apply_effects`, no caso `OutgoingMessage`, agende a cobrança automática:

```python
                case OutgoingMessage(channel=channel, text=text):
                    state.messages.append(
                        Message(channel=channel, author="agent", text=text, at=self._clock.now())
                    )
                    self._arm_auto_followup(state, channel)
```

E acrescente o método:

```python
    def _arm_auto_followup(self, state: SessionState, channel: str) -> None:
        minutes = self._scenario.followup.no_reply_minutes
        identifier = auto_followup_id(channel)
        state.followups = [f for f in state.followups if f.id != identifier]
        state.followups.append(
            Followup(
                id=identifier,
                due_at=self._clock.now() + timedelta(minutes=minutes),
                reason=f"sem resposta de {channel} há {minutes} minutos",
            )
        )
```

- [ ] **Passo 5: rodar e ver passar**

Run: `uv run pytest tests/core/test_followups.py tests/core/test_cycle.py -v`
Esperado: PASS. **Os testes de 02-05 têm que continuar passando sem alteração** —
se algum quebrou, o patch está errado, não o teste.

- [ ] **Passo 6: commit**

```bash
make test && make lint
git add src/core/followups.py src/core/cycle.py tests/core/test_followups.py
git commit -m "feat: follow-up automático por política do cenário, com relógio injetável"
```

## Pronto quando

- Os sete testes passam, e nenhum deles demora mais que milissegundos — se algum
  chamar `time.sleep`, está errado.
- `grep -rn "datetime.now\|time.time" src/core/` não retorna nada fora de
  `clock.py`. Todo o núcleo lê a hora pelo relógio injetado.
