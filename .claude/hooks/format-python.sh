#!/usr/bin/env bash
# Formata o arquivo Python que acabou de ser editado e ordena os imports.
#
# Só `--select I` de propósito: `ruff check --fix` completo apagaria um import
# ainda não usado, e numa edição incremental o uso chega no passo seguinte.
# O resto dos erros fica para o `make lint`, que é quando você quer vê-los.
set -euo pipefail

file=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')

[[ "$file" == *.py ]] || exit 0
[[ -f "$file" ]] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"
uv run ruff format "$file" >/dev/null 2>&1 || true
uv run ruff check --select I --fix "$file" >/dev/null 2>&1 || true
