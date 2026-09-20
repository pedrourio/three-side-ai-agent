# Tarefa 01-01 — Esqueleto Python que se testa e se linta

**Épico:** [01 — Fundação](EPICO.md)
**Spec:** §8 (estratégia de teste), §10 (estrutura), §11 (convenções)
**ADRs:** [0008](../../adr/0008-nucleo-independente-de-framework-web.md)

**Entregável verificável:** `make test` passa em segundos sem rede, e `make
lint` **falha** se alguém importar `fastapi` dentro de `src/core/`.

## Contexto para quem implementa

O projeto é um agente de IA que conversa com três pessoas ao mesmo tempo. A
regra de ouro da arquitetura é que o pacote `core` — onde o agente mora — não
conhece web nem provedor de LLM, porque é isso que permite testá-lo com um
modelo falso, de forma determinística e offline. Esta tarefa não escreve nada do
agente; ela constrói o chão que torna essa regra verificável por ferramenta.

Duas camadas de proteção, de propósito: `import-linter` pega o import estático,
e um teste de runtime pega o caso em que alguém importa dentro de uma função
para driblar o linter.

## Arquivos

- Criar: `pyproject.toml`
- Criar: `Makefile`
- Criar: `.gitignore`
- Criar: `src/core/__init__.py`
- Criar: `src/api/__init__.py`
- Criar: `tests/core/test_boundary.py`
- Criar: `setup.cfg` (contratos do import-linter)

## Interfaces

- Consome: nada, é a primeira tarefa.
- Produz: os pacotes importáveis `core` e `api`, e os alvos `make test`,
  `make lint`, `make fmt`.

## Passos

- [ ] **Passo 1: criar o `pyproject.toml`**

```toml
[project]
name = "three-side-ai-agent"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "pydantic>=2.7",
    "pyyaml>=6.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "ruff>=0.6",
    "import-linter>=2.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/core", "src/api"]

[tool.ruff]
line-length = 100
src = ["src", "tests"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]

[tool.pytest.ini_options]
pythonpath = ["src"]
testpaths = ["tests"]
markers = ["live: precisa de LLM real; fora do make test"]
addopts = "-m 'not live'"
```

- [ ] **Passo 2: criar os pacotes vazios e o `.gitignore`**

```bash
mkdir -p src/core src/api tests/core
touch src/core/__init__.py src/api/__init__.py
cat > .gitignore <<'GIT'
__pycache__/
*.py[cod]
.venv/
.pytest_cache/
.ruff_cache/
.env
data/
node_modules/
.claude/settings.local.json
GIT
uv sync
```

- [ ] **Passo 3: escrever o teste de fronteira, que deve falhar**

`tests/core/test_boundary.py`:

```python
import importlib
import sys

WEB_MODULES = ("fastapi", "uvicorn", "starlette")


def _forget(prefixes: tuple[str, ...]) -> None:
    for name in list(sys.modules):
        if name in prefixes or name.startswith(tuple(p + "." for p in prefixes)):
            del sys.modules[name]


def test_importing_core_does_not_load_a_web_framework():
    """core roda em script de terminal e em teste; não pode arrastar servidor."""
    _forget(("core",) + WEB_MODULES)
    importlib.import_module("core")
    assert not [m for m in WEB_MODULES if m in sys.modules]
```

- [ ] **Passo 4: rodar e ver falhar**

Run: `uv run pytest tests/core/test_boundary.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'core'`, porque `uv sync`
ainda não instalou o projeto ou o `pythonpath` não está ativo. Corrija o que o
erro apontar até o teste passar por mérito, não por acaso.

- [ ] **Passo 5: rodar e ver passar**

Run: `uv run pytest tests/core/test_boundary.py -v`
Esperado: PASS.

- [ ] **Passo 6: declarar o contrato do import-linter**

`setup.cfg`:

```ini
[importlinter]
root_packages =
    core
    api

[importlinter:contract:core-is-standalone]
name = core não depende de api nem de framework web
type = forbidden
source_modules =
    core
forbidden_modules =
    api
    fastapi
    uvicorn
    starlette
```

- [ ] **Passo 7: escrever o `Makefile`**

```makefile
.DEFAULT_GOAL := help

help:  ## lista os alvos
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

test:  ## testes determinísticos, sem rede
	uv run pytest

fmt:  ## formata
	uv run ruff format .
	uv run ruff check --fix .

lint:  ## estilo + fronteira de import
	uv run ruff format --check .
	uv run ruff check .
	uv run lint-imports

.PHONY: help test fmt lint
```

- [ ] **Passo 8: provar que o contrato morde**

Adicione temporariamente `import fastapi` no topo de `src/core/__init__.py`:

Run: `make lint`
Esperado: FAIL com `core is not allowed to import fastapi`. (A mensagem pode
citar `fastapi` como módulo não instalado antes disso — instale-o como dev
dependency temporária ou confie no contrato estático; o import-linter reporta a
violação mesmo sem o pacote presente.)

Remova o import e rode de novo:

Run: `make lint`
Esperado: PASS.

- [ ] **Passo 9: commit**

```bash
git add pyproject.toml Makefile setup.cfg .gitignore uv.lock src tests
git commit -m "chore: esqueleto Python com fronteira core/api verificada por lint"
```

## Pronto quando

- `make test` passa em menos de 5 segundos, offline.
- `make lint` passa no repositório limpo e falha com um `import fastapi` plantado
  em `src/core/`.
- `make` sem argumento lista os alvos.
