# Tarefa 02-03 — Porta de LLM e modelo falso

**Épico:** [02 — Núcleo do agente](EPICO.md)
**Spec:** §4 (gateway), §8 (estratégia de teste)
**ADRs:** [0005](../../adr/0005-litellm-como-gateway-multi-provedor.md),
[0008](../../adr/0008-nucleo-independente-de-framework-web.md)

**Entregável verificável:** o núcleo fala com o LLM por uma interface de um
método só; existe uma implementação real contra o proxy e uma falsa com
respostas roteirizadas, e os testes de todo o resto do projeto usam a falsa.

## Contexto para quem implementa

Esta tarefa é o que torna o resto do épico testável. Sem ela, todo teste do
agente viraria uma chamada de rede não-determinística contra uma cota gratuita.

Duas decisões de desenho que você precisa entender antes de codar:

**A resposta do modelo é só texto + tool calls.** Não há campo estruturado
extra. Se o agente quer continuar trabalhando sozinho no próximo ciclo, ele
chama a tool `keep_working`. Isso mantém a porta compatível com qualquer modelo
que saiba tool calling, que é o mínimo denominador comum entre as camadas
gratuitas.

**O parsing é uma função pura, separada do cliente HTTP.** É ela que tem teste;
o cliente em si só é exercitado pelo teste marcado `live`.

## Arquivos

- Criar: `src/core/llm.py`
- Criar: `src/core/clock.py`
- Criar: `src/core/testing.py`
- Criar: `tests/core/test_llm.py`

## Interfaces

- Consome: nada do núcleo; só `openai` e `pydantic`.
- Produz:
  - `ToolCall(name: str, arguments: dict[str, Any])`
  - `ModelReply(reasoning: str, tool_calls: list[ToolCall])`
  - `ModelPort` (Protocol): `complete(messages: list[dict], tools: list[dict]) -> ModelReply`
  - `LiteLLMModel(base_url, model, api_key)` implementando `ModelPort`
  - `parse_reply(raw: dict) -> ModelReply`
  - `ModelError(RuntimeError)`, `MalformedReply(ModelError)`
  - `core.clock.Clock` (Protocol, `now() -> datetime`) e `SystemClock`
  - `core.testing.FakeModel(replies)` e `core.testing.FakeClock(start)`

## Passos

- [ ] **Passo 1: escrever os testes, que devem falhar**

`tests/core/test_llm.py`:

```python
from datetime import UTC, datetime, timedelta

import pytest

from core.llm import MalformedReply, ModelReply, ToolCall, parse_reply
from core.testing import FakeClock, FakeModel


def test_parses_text_and_tool_calls():
    raw = {
        "content": "Vou perguntar o horário para a clínica.",
        "tool_calls": [
            {
                "function": {
                    "name": "send",
                    "arguments": '{"channel": "s2", "text": "Tem horário na quinta?"}',
                }
            }
        ],
    }

    reply = parse_reply(raw)

    assert reply.reasoning.startswith("Vou perguntar")
    assert reply.tool_calls == [
        ToolCall(name="send", arguments={"channel": "s2", "text": "Tem horário na quinta?"})
    ]


def test_parses_a_reply_with_no_tool_calls():
    reply = parse_reply({"content": "Nada a fazer.", "tool_calls": None})

    assert reply.tool_calls == []


def test_rejects_arguments_that_are_not_json():
    raw = {"content": "", "tool_calls": [{"function": {"name": "send", "arguments": "{oops"}}]}

    with pytest.raises(MalformedReply, match="send"):
        parse_reply(raw)


def test_rejects_a_tool_call_without_a_name():
    raw = {"content": "", "tool_calls": [{"function": {"arguments": "{}"}}]}

    with pytest.raises(MalformedReply):
        parse_reply(raw)


def test_fake_model_returns_scripted_replies_in_order():
    first = ModelReply(reasoning="um", tool_calls=[])
    second = ModelReply(reasoning="dois", tool_calls=[])
    model = FakeModel([first, second])

    assert model.complete([], []) == first
    assert model.complete([], []) == second


def test_fake_model_goes_quiet_when_the_script_ends():
    """Roteiro esgotado devolve resposta vazia: teste nunca vira laço infinito."""
    model = FakeModel([])

    assert model.complete([], []).tool_calls == []


def test_fake_model_records_what_it_was_asked():
    model = FakeModel([])
    model.complete([{"role": "user", "content": "oi"}], [])

    assert model.calls[0][0]["content"] == "oi"


def test_fake_clock_only_moves_when_told():
    clock = FakeClock(datetime(2026, 1, 1, tzinfo=UTC))
    start = clock.now()

    clock.advance(timedelta(minutes=11))

    assert clock.now() - start == timedelta(minutes=11)
```

- [ ] **Passo 2: rodar e ver falhar**

Run: `uv run pytest tests/core/test_llm.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core.llm'`.

- [ ] **Passo 3: implementar `src/core/clock.py`**

```python
from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol


class Clock(Protocol):
    def now(self) -> datetime: ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)
```

- [ ] **Passo 4: implementar `src/core/llm.py`**

```python
from __future__ import annotations

import json
from typing import Any, Protocol

from pydantic import BaseModel, Field


class ModelError(RuntimeError):
    """Falha ao obter uma resposta utilizável do modelo."""


class MalformedReply(ModelError):
    """O modelo respondeu, mas fora do contrato de tool calling."""


class ToolCall(BaseModel):
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)


class ModelReply(BaseModel):
    reasoning: str = ""
    tool_calls: list[ToolCall] = Field(default_factory=list)


class ModelPort(Protocol):
    def complete(self, messages: list[dict], tools: list[dict]) -> ModelReply: ...


def parse_reply(raw: dict) -> ModelReply:
    calls: list[ToolCall] = []
    for entry in raw.get("tool_calls") or []:
        function = entry.get("function") or {}
        name = function.get("name")
        if not name:
            raise MalformedReply(f"tool call sem nome: {entry!r}")

        arguments = function.get("arguments") or "{}"
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except json.JSONDecodeError as error:
                raise MalformedReply(
                    f"argumentos de '{name}' não são JSON válido: {arguments!r}"
                ) from error
        if not isinstance(arguments, dict):
            raise MalformedReply(f"argumentos de '{name}' não são um objeto: {arguments!r}")

        calls.append(ToolCall(name=name, arguments=arguments))

    return ModelReply(reasoning=raw.get("content") or "", tool_calls=calls)


class LiteLLMModel:
    """Fala OpenAI-compatible com o proxy. Não sabe qual provedor atende."""

    def __init__(self, base_url: str, model: str, api_key: str, timeout: float = 60.0) -> None:
        from openai import OpenAI

        self._client = OpenAI(base_url=base_url, api_key=api_key, timeout=timeout)
        self._model = model

    def complete(self, messages: list[dict], tools: list[dict]) -> ModelReply:
        from openai import OpenAIError

        try:
            response = self._client.chat.completions.create(
                model=self._model,
                messages=messages,
                tools=tools,
                tool_choice="auto",
            )
        except OpenAIError as error:
            raise ModelError(f"nenhum provedor atendeu: {error}") from error

        return parse_reply(response.choices[0].message.model_dump())
```

Os imports de `openai` ficam dentro dos métodos de propósito: importar `core`
não deve puxar cliente HTTP, e o teste de fronteira da tarefa 01-01 é mais fácil
de estender assim.

- [ ] **Passo 5: implementar `src/core/testing.py`**

```python
"""Dublês para os testes. Vive em src/ porque os testes de api/ também usam."""

from __future__ import annotations

from datetime import datetime, timedelta

from core.llm import ModelReply


class FakeModel:
    """Devolve respostas roteirizadas, em ordem. Roteiro esgotado = silêncio."""

    def __init__(self, replies: list[ModelReply]) -> None:
        self._replies = list(replies)
        self.calls: list[list[dict]] = []

    def complete(self, messages: list[dict], tools: list[dict]) -> ModelReply:
        self.calls.append(messages)
        if not self._replies:
            return ModelReply(reasoning="(roteiro esgotado)")
        return self._replies.pop(0)


class FakeClock:
    def __init__(self, start: datetime) -> None:
        self._now = start

    def now(self) -> datetime:
        return self._now

    def advance(self, delta: timedelta) -> None:
        self._now += delta
```

- [ ] **Passo 6: rodar e ver passar**

Run: `uv run pytest tests/core/test_llm.py -v`
Esperado: PASS, oito testes.

- [ ] **Passo 7: escrever o teste marcado `live`**

`tests/live/test_real_model.py`:

```python
import os

import pytest

from core.llm import LiteLLMModel

pytestmark = pytest.mark.live


def test_the_proxy_answers_with_a_tool_call():
    model = LiteLLMModel(
        base_url=os.environ.get("LLM_BASE_URL", "http://localhost:4000"),
        model=os.environ.get("LLM_MODEL", "primary-agent"),
        api_key=os.environ.get("LLM_API_KEY", "sk-local-dev"),
    )
    tools = [
        {
            "type": "function",
            "function": {
                "name": "send",
                "description": "Envia mensagem a um canal.",
                "parameters": {
                    "type": "object",
                    "properties": {"channel": {"type": "string"}, "text": {"type": "string"}},
                    "required": ["channel", "text"],
                },
            },
        }
    ]

    reply = model.complete(
        [{"role": "user", "content": "Use a tool send para dizer 'oi' ao canal s2."}],
        tools,
    )

    assert reply.tool_calls and reply.tool_calls[0].name == "send"
```

Run: `make up && uv run pytest -m live -v`
Esperado: PASS. Se falhar porque o modelo gratuito ignora tool calling, troque a
ordem dos provedores em `litellm/config.yaml` — é exatamente o risco previsto na
spec §13, e o custo de contorná-lo é uma linha de YAML.

Confirme também que `make test` **não** roda este teste.

- [ ] **Passo 8: commit**

```bash
git add src/core/llm.py src/core/clock.py src/core/testing.py tests/core/test_llm.py tests/live
git commit -m "feat: porta de LLM com parsing testável, cliente do proxy e dublês"
```

## Pronto quando

- `make test` passa e não faz nenhuma chamada de rede.
- `uv run pytest -m live` passa com o Compose de pé.
- `make lint` continua verde: `core` não importa nada de web.
