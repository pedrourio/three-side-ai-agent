# Tarefa 02-01 — Cenário como dado, validado na carga

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §6 (cenário como dado)
**ADRs:** [0002](../../adr/0002-agente-unico-com-estado-compartilhado.md)

**Entregável verificável:** `scenarios/appointment-scheduling.yaml` carrega em um
objeto tipado, e um cenário com erro — canal inexistente, ciclo de dependência —
falha na carga com mensagem que diz exatamente o quê, não no meio da demo.

## Contexto para quem implementa

O agente não conhece consultas médicas. Ele conhece "três canais, um objetivo, um
conjunto de fatos com dependências entre si". O cenário é o arquivo que
instancia isso. A validação é agressiva de propósito: um cenário que declara
`depends_on: [especialidad]` (com erro de digitação) faria a propagação de
invalidação silenciosamente não acontecer, e esse é o bug mais caro possível
neste projeto — o sistema parece funcionar.

As **chaves** do YAML são em inglês; o **conteúdo** (`label`, `role`, `name`,
`goal`) é texto que vai para o prompt e para a tela, portanto em português.

## Arquivos

- Criar: `src/core/scenario.py`
- Criar: `scenarios/appointment-scheduling.yaml`
- Criar: `tests/core/test_scenario.py`

## Interfaces

- Consome: nada além do esqueleto (tarefa 01-01).
- Produz:
  - `Channel(id, label, role)`
  - `FactSpec(name, source, confirmation, depends_on)`
  - `FollowupPolicy(no_reply_minutes)`
  - `Scenario(id, name, goal, channels, facts, followup)` com
    `channel_ids() -> set[str]`, `fact_spec(name) -> FactSpec`,
    `dependents_of(name) -> list[str]` (dependentes diretos)
  - `load_scenario(path: Path) -> Scenario`
  - `ScenarioError(ValueError)`

## Passos

- [ ] **Passo 1: escrever os testes, que devem falhar**

`tests/core/test_scenario.py`:

```python
from pathlib import Path

import pytest

from core.scenario import ScenarioError, load_scenario

VALID = """
id: t
name: Teste
goal: Combinar um horário.
channels:
  - {id: a, label: A, role: Pede.}
  - {id: b, label: B, role: Confirma.}
facts:
  - {name: topic, source: [a], confirmation: [b]}
  - {name: slot, source: [b], confirmation: [a], depends_on: [topic]}
"""


def write(tmp_path: Path, body: str) -> Path:
    path = tmp_path / "scenario.yaml"
    path.write_text(body)
    return path


def test_loads_a_valid_scenario(tmp_path):
    scenario = load_scenario(write(tmp_path, VALID))

    assert scenario.id == "t"
    assert scenario.channel_ids() == {"a", "b"}
    assert scenario.fact_spec("slot").depends_on == ["topic"]
    assert scenario.dependents_of("topic") == ["slot"]
    assert scenario.followup.no_reply_minutes == 10  # default


def test_rejects_fact_whose_source_is_not_a_channel(tmp_path):
    body = VALID.replace("{name: topic, source: [a]", "{name: topic, source: [z]")

    with pytest.raises(ScenarioError, match="topic.*z"):
        load_scenario(write(tmp_path, body))


def test_rejects_dependency_on_unknown_fact(tmp_path):
    body = VALID.replace("depends_on: [topic]", "depends_on: [topci]")

    with pytest.raises(ScenarioError, match="topci"):
        load_scenario(write(tmp_path, body))


def test_rejects_dependency_cycle(tmp_path):
    body = VALID.replace(
        "{name: topic, source: [a], confirmation: [b]}",
        "{name: topic, source: [a], confirmation: [b], depends_on: [slot]}",
    )

    with pytest.raises(ScenarioError, match="ciclo"):
        load_scenario(write(tmp_path, body))


def test_rejects_duplicate_fact_names(tmp_path):
    body = VALID + "  - {name: slot, source: [a]}\n"

    with pytest.raises(ScenarioError, match="slot"):
        load_scenario(write(tmp_path, body))


def test_shipped_scenario_is_valid():
    scenario = load_scenario(Path("scenarios/appointment-scheduling.yaml"))

    assert scenario.channel_ids() == {"s1", "s2", "p"}
    assert "slot" in {fact.name for fact in scenario.facts}
```

- [ ] **Passo 2: rodar e ver falhar**

Run: `uv run pytest tests/core/test_scenario.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.scenario'`.

- [ ] **Passo 3: implementar `src/core/scenario.py`**

```python
from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import BaseModel, Field, ValidationError


class ScenarioError(ValueError):
    """Cenário sintaticamente ou semanticamente inválido."""


class Channel(BaseModel):
    id: str
    label: str
    role: str


class FactSpec(BaseModel):
    name: str
    source: list[str]
    confirmation: list[str] = Field(default_factory=list)
    depends_on: list[str] = Field(default_factory=list)


class FollowupPolicy(BaseModel):
    no_reply_minutes: int = 10


class Scenario(BaseModel):
    id: str
    name: str
    goal: str
    channels: list[Channel]
    facts: list[FactSpec]
    followup: FollowupPolicy = Field(default_factory=FollowupPolicy)

    def channel_ids(self) -> set[str]:
        return {channel.id for channel in self.channels}

    def fact_spec(self, name: str) -> FactSpec:
        for fact in self.facts:
            if fact.name == name:
                return fact
        raise KeyError(name)

    def dependents_of(self, name: str) -> list[str]:
        return [fact.name for fact in self.facts if name in fact.depends_on]


def load_scenario(path: Path) -> Scenario:
    try:
        raw = yaml.safe_load(Path(path).read_text())
    except yaml.YAMLError as error:
        raise ScenarioError(f"YAML inválido em {path}: {error}") from error

    try:
        scenario = Scenario.model_validate(raw)
    except ValidationError as error:
        raise ScenarioError(f"Cenário inválido em {path}: {error}") from error

    _check_semantics(scenario, path)
    return scenario


def _check_semantics(scenario: Scenario, path: Path) -> None:
    channels = scenario.channel_ids()
    if len(channels) != len(scenario.channels):
        raise ScenarioError(f"{path}: ids de canal repetidos")

    names: list[str] = []
    for fact in scenario.facts:
        if fact.name in names:
            raise ScenarioError(f"{path}: fato '{fact.name}' declarado duas vezes")
        names.append(fact.name)

    for fact in scenario.facts:
        for channel in fact.source:
            if channel not in channels:
                raise ScenarioError(
                    f"{path}: fato '{fact.name}' tem source '{channel}', que não é um canal"
                )
        for channel in fact.confirmation:
            if channel not in channels:
                raise ScenarioError(
                    f"{path}: fato '{fact.name}' pede confirmação de '{channel}', "
                    "que não é um canal"
                )
        for dependency in fact.depends_on:
            if dependency not in names:
                raise ScenarioError(
                    f"{path}: fato '{fact.name}' depende de '{dependency}', que não existe"
                )

    _check_acyclic(scenario, path)


def _check_acyclic(scenario: Scenario, path: Path) -> None:
    visiting: set[str] = set()
    done: set[str] = set()

    def walk(name: str) -> None:
        if name in done:
            return
        if name in visiting:
            raise ScenarioError(f"{path}: ciclo de dependência envolvendo '{name}'")
        visiting.add(name)
        for dependency in scenario.fact_spec(name).depends_on:
            walk(dependency)
        visiting.discard(name)
        done.add(name)

    for fact in scenario.facts:
        walk(fact.name)
```

- [ ] **Passo 4: escrever `scenarios/appointment-scheduling.yaml`**

```yaml
id: appointment-scheduling
name: Agendamento de consulta
goal: >
  Agendar uma consulta para o colaborador indicado por S1, em horário que exista
  na agenda de S2 e que P aceite.

channels:
  - id: s1
    label: Secretária da empresa
    role: >
      Solicita o agendamento. Sabe quem é o colaborador e qual a urgência.
      Não conhece a agenda da clínica.
  - id: s2
    label: Secretária da clínica
    role: >
      Única que conhece e reserva horários na agenda. Não conhece o paciente.
  - id: p
    label: Paciente
    role: >
      Aceita ou recusa o horário proposto. Pode ter restrições próprias.

facts:
  - name: employee
    source: [s1]
    confirmation: []
  - name: specialty
    source: [s1]
    confirmation: [s2]
  - name: slot
    source: [s2]
    confirmation: [p, s1]
    depends_on: [specialty]
  - name: booking
    source: [s2]
    confirmation: [s2]
    depends_on: [slot]

followup:
  no_reply_minutes: 10
```

- [ ] **Passo 5: rodar e ver passar**

Run: `uv run pytest tests/core/test_scenario.py -v`
Esperado: PASS, seis testes.

- [ ] **Passo 6: commit**

```bash
git add src/core/scenario.py scenarios/appointment-scheduling.yaml tests/core/test_scenario.py
git commit -m "feat: cenário como dado, com validação semântica na carga"
```

## Pronto quando

- Os seis testes passam.
- Trocar `depends_on: [specialty]` por `[speciality]` no arquivo real faz
  `make test` falhar com mensagem apontando o fato e a dependência inexistente.
