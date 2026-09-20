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
