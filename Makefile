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

up:  ## sobe postgres, litellm e api
	docker compose up -d --build

down:  ## derruba tudo
	docker compose down

logs:  ## acompanha os logs
	docker compose logs -f

ping:  ## confere que o proxy responde com um modelo real
	uv run python scripts/ping_model.py

.PHONY: help test fmt lint up down logs ping
