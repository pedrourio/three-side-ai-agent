# Tarefa 02-02 — Quadro de fatos e propagação de invalidação

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §5.1 (estado), §5.4 (conflito)
**ADRs:** [0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md)

**Entregável verificável:** S2 propõe 14h, P e S1 confirmam, S2 registra a
reserva — e então P pede 16h. Sem nenhum LLM envolvido, a reserva de S2 cai para
`needs_reconfirmation` e suas confirmações somem.

## Contexto para quem implementa

Esta é a tarefa mais importante do épico, e a mais fácil de subestimar. O
[ADR 0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md) decidiu que
a **contabilidade** de quem confirmou o quê é responsabilidade do código, e não
do agente — justamente porque um agente esquecendo uma confirmação em silêncio é
o modo de falha que parece sucesso.

O que o código faz aqui é puramente mecânico e totalmente testável: quando um
fato muda de valor ou é invalidado, todo fato que depende dele (transitivamente)
perde suas confirmações. O que fazer a respeito disso — avisar quem, em que
ordem, renegociar ou desistir — não é assunto deste arquivo; é do agente.

## Arquivos

- Criar: `src/core/facts.py`
- Criar: `tests/core/test_facts.py`

## Interfaces

- Consome: `Scenario`, `FactSpec` de `core.scenario` (tarefa 02-01).
- Produz:
  - `FactStatus` (`StrEnum`): `PROPOSED`, `CONFIRMED`, `NEEDS_RECONFIRMATION`,
    `INVALIDATED`
  - `Fact(name, value, source, status, confirmed_by)`
  - `FactChange(fact, before, after, reason)`
  - `FactsBoard(scenario)` com `record(name, value, source) -> list[FactChange]`,
    `confirm(name, channel) -> list[FactChange]`,
    `invalidate(name, reason) -> list[FactChange]`,
    `snapshot() -> dict[str, Fact]`, e
    `FactsBoard.from_snapshot(scenario, snapshot) -> FactsBoard`
  - `FactError(ValueError)`

## Regras que os testes fixam

1. Fato sem ninguém na lista de `confirmation` nasce já `CONFIRMED` ao ser
   registrado.
2. Fato com `confirmation` nasce `PROPOSED`, e vira `CONFIRMED` quando **todos**
   os canais listados confirmaram.
3. Registrar o **mesmo valor** de novo não é mudança: retorna lista vazia e não
   propaga.
4. Registrar valor **diferente** zera as confirmações do próprio fato e propaga
   aos dependentes.
5. `invalidate` marca `INVALIDATED`, zera confirmações e propaga.
6. Propagação é **transitiva** e atinge só fatos que já tinham valor. Atenção:
   "não mexer no status" e "não propagar adiante" são coisas diferentes — parar a
   recursão num fato já `needs_reconfirmation` deixa um dependente `confirmed`
   com a cadeia quebrada embaixo dele, que é exatamente o silêncio que o
   [ADR 0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md) proíbe.
7. `record` de um canal fora de `source`, ou `confirm` de um canal fora de
   `confirmation`, levanta `FactError` — é erro de uso do agente, e o ciclo trata
   isso como tool call malformada (tarefa 02-04).

## Passos

- [ ] **Passo 1: escrever os testes, que devem falhar**

`tests/core/test_facts.py`:

```python
import pytest

from core.facts import FactError, FactsBoard, FactStatus
from core.scenario import Channel, FactSpec, Scenario


def make_scenario() -> Scenario:
    return Scenario(
        id="t",
        name="Teste",
        goal="Combinar.",
        channels=[
            Channel(id="s1", label="S1", role="Pede."),
            Channel(id="s2", label="S2", role="Agenda."),
            Channel(id="p", label="P", role="Aceita."),
        ],
        facts=[
            FactSpec(name="employee", source=["s1"]),
            FactSpec(name="specialty", source=["s1"], confirmation=["s2"]),
            FactSpec(
                name="slot", source=["s2"], confirmation=["p", "s1"], depends_on=["specialty"]
            ),
            FactSpec(name="booking", source=["s2"], confirmation=["s2"], depends_on=["slot"]),
        ],
    )


@pytest.fixture
def board() -> FactsBoard:
    return FactsBoard(make_scenario())


def test_fact_without_confirmers_is_confirmed_on_record(board):
    board.record("employee", "João", source="s1")

    assert board.snapshot()["employee"].status is FactStatus.CONFIRMED


def test_fact_with_confirmers_starts_proposed(board):
    board.record("specialty", "cardiologia", source="s1")

    assert board.snapshot()["specialty"].status is FactStatus.PROPOSED


def test_fact_becomes_confirmed_only_after_every_confirmer(board):
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")

    assert board.snapshot()["slot"].status is FactStatus.PROPOSED

    board.confirm("slot", "s1")

    assert board.snapshot()["slot"].status is FactStatus.CONFIRMED
    assert set(board.snapshot()["slot"].confirmed_by) == {"p", "s1"}


def test_recording_the_same_value_is_not_a_change(board):
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")

    changes = board.record("slot", "14h", source="s2")

    assert changes == []
    assert board.snapshot()["slot"].confirmed_by == ["p"]


def test_changing_a_value_drops_its_own_confirmations(board):
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")
    board.confirm("slot", "s1")

    board.record("slot", "16h", source="s2")

    slot = board.snapshot()["slot"]
    assert slot.status is FactStatus.PROPOSED
    assert slot.confirmed_by == []


def test_changing_a_value_propagates_to_dependents(board):
    """O caso que dá nome ao projeto: P pede outro horário depois de S2 reservar."""
    board.record("specialty", "cardiologia", source="s1")
    board.confirm("specialty", "s2")
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")
    board.confirm("slot", "s1")
    board.record("booking", "#123", source="s2")
    board.confirm("booking", "s2")

    assert board.snapshot()["booking"].status is FactStatus.CONFIRMED

    changes = board.record("slot", "16h", source="s2")

    booking = board.snapshot()["booking"]
    assert booking.status is FactStatus.NEEDS_RECONFIRMATION
    assert booking.confirmed_by == []
    assert booking.value == "#123", "o valor antigo é preservado; só a confiança caiu"
    assert {change.fact for change in changes} == {"slot", "booking"}


def test_propagation_is_transitive(board):
    board.record("specialty", "cardiologia", source="s1")
    board.confirm("specialty", "s2")
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")
    board.confirm("slot", "s1")
    board.record("booking", "#123", source="s2")
    board.confirm("booking", "s2")

    board.record("specialty", "ortopedia", source="s1")

    snapshot = board.snapshot()
    assert snapshot["slot"].status is FactStatus.NEEDS_RECONFIRMATION
    assert snapshot["booking"].status is FactStatus.NEEDS_RECONFIRMATION


def test_propagation_skips_facts_that_never_had_a_value(board):
    board.record("specialty", "cardiologia", source="s1")
    changes = board.record("specialty", "ortopedia", source="s1")

    assert {change.fact for change in changes} == {"specialty"}
    assert board.snapshot()["slot"].status is FactStatus.PROPOSED
    assert board.snapshot()["slot"].value is None


def test_propagation_does_not_stop_at_an_already_broken_link(board):
    """slot já está needs_reconfirmation; booking, confirmado depois, não pode ficar verde."""
    board.record("specialty", "cardiologia", source="s1")
    board.confirm("specialty", "s2")
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")
    board.confirm("slot", "s1")
    board.record("specialty", "ortopedia", source="s1")  # quebra slot
    board.record("booking", "#123", source="s2")
    board.confirm("booking", "s2")

    board.record("specialty", "neurologia", source="s1")

    assert board.snapshot()["booking"].status is FactStatus.NEEDS_RECONFIRMATION


def test_invalidate_drops_confirmations_and_propagates(board):
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")
    board.record("booking", "#123", source="s2")
    board.confirm("booking", "s2")

    board.invalidate("slot", reason="S1 cancelou a consulta")

    snapshot = board.snapshot()
    assert snapshot["slot"].status is FactStatus.INVALIDATED
    assert snapshot["booking"].status is FactStatus.NEEDS_RECONFIRMATION


def test_wrong_source_is_an_error(board):
    with pytest.raises(FactError, match="slot"):
        board.record("slot", "14h", source="p")


def test_wrong_confirmer_is_an_error(board):
    board.record("slot", "14h", source="s2")

    with pytest.raises(FactError, match="s2"):
        board.confirm("slot", "s2")


def test_unknown_fact_is_an_error(board):
    with pytest.raises(FactError, match="wat"):
        board.record("wat", "x", source="s1")


def test_snapshot_round_trips(board):
    board.record("slot", "14h", source="s2")
    board.confirm("slot", "p")

    restored = FactsBoard.from_snapshot(make_scenario(), board.snapshot())

    assert restored.snapshot() == board.snapshot()
```

- [ ] **Passo 2: rodar e ver falhar**

Run: `uv run pytest tests/core/test_facts.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.facts'`.

- [ ] **Passo 3: implementar `src/core/facts.py`**

```python
from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field

from core.scenario import Scenario


class FactError(ValueError):
    """Uso inválido do quadro de fatos: fato inexistente, canal errado."""


class FactStatus(StrEnum):
    PROPOSED = "proposed"
    CONFIRMED = "confirmed"
    NEEDS_RECONFIRMATION = "needs_reconfirmation"
    INVALIDATED = "invalidated"


class Fact(BaseModel):
    name: str
    value: str | None = None
    source: str | None = None
    status: FactStatus = FactStatus.PROPOSED
    confirmed_by: list[str] = Field(default_factory=list)


class FactChange(BaseModel):
    fact: str
    before: Fact
    after: Fact
    reason: str


class FactsBoard:
    def __init__(self, scenario: Scenario) -> None:
        self._scenario = scenario
        self._facts = {spec.name: Fact(name=spec.name) for spec in scenario.facts}

    @classmethod
    def from_snapshot(cls, scenario: Scenario, snapshot: dict[str, Fact]) -> FactsBoard:
        board = cls(scenario)
        board._facts = {name: fact.model_copy(deep=True) for name, fact in snapshot.items()}
        return board

    def snapshot(self) -> dict[str, Fact]:
        return {name: fact.model_copy(deep=True) for name, fact in self._facts.items()}

    def record(self, name: str, value: str, source: str) -> list[FactChange]:
        spec = self._spec(name)
        if source not in spec.source:
            raise FactError(
                f"canal '{source}' não pode originar o fato '{name}'; "
                f"apenas {spec.source}"
            )

        before = self._facts[name]
        if before.value == value and before.status is not FactStatus.INVALIDATED:
            return []

        after = Fact(
            name=name,
            value=value,
            source=source,
            confirmed_by=[],
            status=FactStatus.CONFIRMED if not spec.confirmation else FactStatus.PROPOSED,
        )
        self._facts[name] = after
        changes = [FactChange(fact=name, before=before, after=after, reason=f"{source} informou")]
        changes += self._cascade(name)
        return changes

    def confirm(self, name: str, channel: str) -> list[FactChange]:
        spec = self._spec(name)
        if channel not in spec.confirmation:
            raise FactError(
                f"canal '{channel}' não confirma o fato '{name}'; "
                f"apenas {spec.confirmation}"
            )

        before = self._facts[name]
        if channel in before.confirmed_by:
            return []

        after = before.model_copy(deep=True)
        after.confirmed_by = [*before.confirmed_by, channel]
        if set(after.confirmed_by) >= set(spec.confirmation):
            after.status = FactStatus.CONFIRMED
        elif after.status is FactStatus.NEEDS_RECONFIRMATION:
            after.status = FactStatus.PROPOSED

        self._facts[name] = after
        return [FactChange(fact=name, before=before, after=after, reason=f"{channel} confirmou")]

    def invalidate(self, name: str, reason: str) -> list[FactChange]:
        before = self._spec_and_fact(name)[1]

        after = before.model_copy(deep=True)
        after.status = FactStatus.INVALIDATED
        after.confirmed_by = []
        self._facts[name] = after

        changes = [FactChange(fact=name, before=before, after=after, reason=reason)]
        changes += self._cascade(name)
        return changes

    def _cascade(self, name: str, seen: set[str] | None = None) -> list[FactChange]:
        seen = seen if seen is not None else {name}
        changes: list[FactChange] = []

        for dependent in self._scenario.dependents_of(name):
            if dependent in seen:
                continue
            seen.add(dependent)

            before = self._facts[dependent]
            untouched = before.value is None or before.status in (
                FactStatus.NEEDS_RECONFIRMATION,
                FactStatus.INVALIDATED,
            )
            if not untouched:
                after = before.model_copy(deep=True)
                after.status = FactStatus.NEEDS_RECONFIRMATION
                after.confirmed_by = []
                self._facts[dependent] = after
                changes.append(
                    FactChange(
                        fact=dependent,
                        before=before,
                        after=after,
                        reason=f"depende de '{name}', que mudou",
                    )
                )

            # sempre desce a cadeia, mesmo sem mexer neste nó
            changes += self._cascade(dependent, seen)

        return changes

    def _spec(self, name: str):
        return self._spec_and_fact(name)[0]

    def _spec_and_fact(self, name: str):
        try:
            spec = self._scenario.fact_spec(name)
        except KeyError:
            raise FactError(f"fato '{name}' não existe neste cenário") from None
        return spec, self._facts[name]
```

- [ ] **Passo 4: rodar e ver passar**

Run: `uv run pytest tests/core/test_facts.py -v`
Esperado: PASS, catorze testes. Se `test_propagation_is_transitive` falhar,
provavelmente `_cascade` está parando no primeiro nível.

- [ ] **Passo 5: commit**

```bash
git add src/core/facts.py tests/core/test_facts.py
git commit -m "feat: quadro de fatos com propagação transitiva de invalidação"
```

## Pronto quando

- Os catorze testes passam, offline, em menos de um segundo.
- O teste `test_changing_a_value_propagates_to_dependents` é o que prova o
  requisito central do projeto — se ele for removido ou enfraquecido, o
  [ADR 0004](../../adr/0004-codigo-propaga-invalidacao-agente-julga.md) deixou de
  ser verdade.
