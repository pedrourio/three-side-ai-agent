# Tarefa 01-02 — Compose com Postgres e LiteLLM respondendo

**Épico:** [01 — Fundação](EPICO.md)
**Spec:** §4 (arquitetura), §13 (riscos de cota)
**ADRs:** [0005](../../adr/0005-litellm-como-gateway-multi-provedor.md),
[0009](../../adr/0009-postgres-como-banco-da-sessao.md)

**Entregável verificável:** `make up` sobe `postgres`, `litellm` e `api`, nessa
ordem de dependência; `make ping` obtém uma resposta de um modelo gratuito real
através do proxy, sem que o código saiba qual provedor atendeu.

## Contexto para quem implementa

O agente nunca fala com Gemini, Groq ou OpenRouter diretamente. Ele fala um
único protocolo (OpenAI-compatible) com um proxy local, e o proxy decide quem
atende, com fallback em cascata quando um provedor estoura cota. Isso importa
porque este é um projeto sem orçamento: as camadas gratuitas têm limite de taxa
e mudam de condição sem aviso.

O nome lógico do modelo é `primary-agent`. Esse nome é a **única** coisa que o
código conhece.

## Arquivos

- Criar: `compose.yaml`
- Criar: `litellm/config.yaml`
- Criar: `.env.example`
- Criar: `Dockerfile`
- Criar: `src/api/main.py`
- Criar: `scripts/ping_model.py`
- Modificar: `Makefile` (alvos `up`, `down`, `logs`, `ping`)
- Modificar: `pyproject.toml` (dependências `fastapi`, `uvicorn`, `openai`)

## Interfaces

- Consome: o esqueleto e os alvos de `make` da tarefa 01-01.
- Produz:
  - variáveis `LLM_BASE_URL` (default `http://litellm:4000`), `LLM_MODEL`
    (default `primary-agent`), `LLM_API_KEY`, `DATABASE_URL`;
  - endpoint `GET /health` retornando `{"status": "ok"}`;
  - `scripts/ping_model.py`, usado só por humano, nunca por teste.

## Passos

- [ ] **Passo 1: adicionar as dependências**

```bash
uv add fastapi "uvicorn[standard]" openai "psycopg[binary]"
```

- [ ] **Passo 2: escrever o teste do healthcheck, que deve falhar**

`tests/api/test_health.py`:

```python
from fastapi.testclient import TestClient

from api.main import app


def test_health_reports_ok():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Passo 3: rodar e ver falhar**

Run: `uv run pytest tests/api/test_health.py -v`
Esperado: FAIL — `ModuleNotFoundError: No module named 'api.main'`.

- [ ] **Passo 4: implementar o mínimo**

`src/api/main.py`:

```python
from fastapi import FastAPI

app = FastAPI(title="three-side-ai-agent")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Passo 5: rodar e ver passar**

Run: `uv run pytest tests/api/test_health.py -v`
Esperado: PASS. Rode `make lint` também: o contrato do import-linter permite
`api` importar `fastapi`, e continua proibindo o caminho inverso.

- [ ] **Passo 6: escrever o `Dockerfile`**

```dockerfile
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONPATH=/app/src

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

COPY src ./src
COPY scenarios ./scenarios

CMD ["uv", "run", "--no-dev", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Crie `scenarios/.gitkeep` para o `COPY` não falhar antes da tarefa 02-01.

- [ ] **Passo 7: escrever `litellm/config.yaml`**

A ordem da lista é a ordem do fallback. Todos os três têm camada gratuita; o
`primary-agent` aponta para o primeiro que responder.

```yaml
model_list:
  - model_name: primary-agent
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: os.environ/GEMINI_API_KEY
  - model_name: primary-agent
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: os.environ/GROQ_API_KEY
  - model_name: primary-agent
    litellm_params:
      model: openrouter/meta-llama/llama-3.3-70b-instruct:free
      api_key: os.environ/OPENROUTER_API_KEY

router_settings:
  num_retries: 2
  allowed_fails: 1
  cooldown_time: 60

litellm_settings:
  drop_params: true
```

- [ ] **Passo 8: escrever `.env.example` e `compose.yaml`**

`.env.example`:

```bash
# pelo menos uma destas precisa estar preenchida
GEMINI_API_KEY=
GROQ_API_KEY=
OPENROUTER_API_KEY=

# chave que a api usa para falar com o proxy local; qualquer string
LITELLM_MASTER_KEY=sk-local-dev

# banco local; o mesmo valor é usado pelo make test-db
POSTGRES_USER=agent
POSTGRES_PASSWORD=agent
POSTGRES_DB=agent
DATABASE_URL=postgresql://agent:agent@localhost:5432/agent
```

`compose.yaml`. Note o `DATABASE_URL` da `api` apontando para o host
`postgres`, e o do `.env` apontando para `localhost` — o primeiro é de dentro da
rede do Compose, o segundo é para você e para o `make test-db`.

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - agent-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    volumes:
      - ./litellm/config.yaml:/app/config.yaml:ro
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      GEMINI_API_KEY: ${GEMINI_API_KEY:-}
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:-}
    ports:
      - "4000:4000"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')"]
      interval: 10s
      timeout: 3s
      retries: 10

  api:
    build: .
    environment:
      LLM_BASE_URL: http://litellm:4000
      LLM_MODEL: primary-agent
      LLM_API_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
    volumes:
      - ./src:/app/src
      - ./scenarios:/app/scenarios
    ports:
      - "8000:8000"
    depends_on:
      litellm:
        condition: service_healthy
      postgres:
        condition: service_healthy

volumes:
  agent-data:
```

- [ ] **Passo 9: escrever o script de ping**

`scripts/ping_model.py`:

```python
"""Confere que o proxy responde. Uso humano; nunca importado por teste."""

import os

from openai import OpenAI

client = OpenAI(
    base_url=os.environ.get("LLM_BASE_URL", "http://localhost:4000"),
    api_key=os.environ.get("LLM_API_KEY", "sk-local-dev"),
)

reply = client.chat.completions.create(
    model=os.environ.get("LLM_MODEL", "primary-agent"),
    messages=[{"role": "user", "content": "Responda apenas: pong"}],
)

print(reply.choices[0].message.content)
print(f"(atendido por: {reply.model})")
```

- [ ] **Passo 10: estender o `Makefile`**

```makefile
up:  ## sobe api e litellm
	docker compose up -d --build

down:  ## derruba tudo
	docker compose down

logs:  ## acompanha os logs
	docker compose logs -f

ping:  ## confere que o proxy responde com um modelo real
	uv run python scripts/ping_model.py

.PHONY: help test fmt lint up down logs ping
```

- [ ] **Passo 11: subir e verificar**

```bash
cp .env.example .env   # preencha ao menos uma chave gratuita
make up
docker compose ps               # postgres e litellm healthy, api up
curl -s localhost:8000/health   # {"status":"ok"}
make ping                       # pong + qual provedor atendeu
psql "$DATABASE_URL" -c 'select 1'   # o banco aceita conexão de fora do Compose
```

Se o `ping` falhar, `make logs` mostra qual provedor recusou e por quê. Testar o
fallback é simples: inverta a ordem em `litellm/config.yaml`, ou apague uma
chave do `.env` e confirme que o próximo da lista atende.

- [ ] **Passo 12: commit**

```bash
git add compose.yaml Dockerfile litellm .env.example scripts src/api tests/api Makefile pyproject.toml uv.lock
git commit -m "feat: compose com api e gateway litellm multi-provedor"
```

## Pronto quando

- `make up` sobe os três serviços; `postgres` e `litellm` ficam `healthy` antes
  de a `api` subir, e `curl localhost:8000/health` responde.
- `DATABASE_URL` do `.env` conecta de fora do Compose — é o que o `make test-db`
  vai usar na tarefa 02-07.
- `make ping` imprime a resposta de um modelo real e o nome do provedor.
- Derrubar o primeiro provedor (apagando sua chave) faz o segundo atender, sem
  mudança de código.
- `.env` está no `.gitignore` e nenhuma chave foi commitada.
