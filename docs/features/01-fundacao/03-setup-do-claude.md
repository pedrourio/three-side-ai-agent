# Tarefa 01-03 — Setup versionável do Claude

**Épico:** [01 — Fundação](EPICO.md)
**Spec:** §9 (setup versionável), §12 (processo de trabalho)
**ADRs:** [0001](../../adr/0001-usar-adrs-para-decisoes-arquiteturais.md),
[0008](../../adr/0008-nucleo-independente-de-framework-web.md)

**Entregável verificável:** uma sessão nova do Claude, sem nenhum contexto desta
conversa, consegue pegar uma tarefa do backlog e começar a implementar com as
regras certas; e `/adr` cria o próximo ADR numerado.

## Contexto para quem implementa

O erro clássico aqui é transformar o `CLAUDE.md` em despejo de documentação. Ele
compete por contexto com o código, é lido em toda sessão, e quanto maior, menos
eficaz. Regra: **só entra o que muda o comportamento**. Descrição de arquitetura
mora no spec e é referenciada, não colada.

## Arquivos

- Criar: `CLAUDE.md`
- Criar: `.claude/settings.json`
- Criar: `.claude/hooks/format-python.sh`
- Criar: `.claude/commands/tarefa.md`
- Criar: `.claude/commands/adr.md`
- Modificar: `.gitignore` (já ignora `.claude/settings.local.json` desde 01-01)

## Interfaces

- Consome: os alvos de `make` das tarefas 01-01 e 01-02.
- Produz: os comandos `/tarefa <caminho>` e `/adr <título>`.

## Passos

- [ ] **Passo 1: escrever o `CLAUDE.md`**

```markdown
# three-side-ai-agent

Um agente de IA que conversa simultaneamente com três pessoas — cada uma com
parte da informação, nenhuma falando com as outras — para completar um objetivo
único. O desafio é coordenar estado sob efeitos cruzados, não conversar.

Desenho completo: @docs/superpowers/specs/2026-09-19-three-side-ai-agent-design.md
Decisões e seus porquês: @docs/adr/README.md
Backlog: @docs/features/README.md

## Comandos

- `make test` — testes determinísticos, sem rede nem chave de API. Sempre rode
  antes de dizer que terminou.
- `make lint` — estilo (ruff) + fronteira de import (import-linter).
- `make up` / `make down` / `make logs` — Compose.
- `make ping` — confere que o gateway de LLM responde com um modelo real.
- `make types` — gera os tipos TypeScript a partir dos modelos Pydantic.

## Regras de fronteira

- `src/core/` NÃO importa `src/api/`, `fastapi` nem `uvicorn`. É o que mantém o
  agente testável sem servidor. `make lint` falha se você quebrar.
- Tipos TypeScript de contrato do backend são **gerados**, nunca escritos à mão.
- Teste que precise de LLM real leva `@pytest.mark.live` e fica fora do
  `make test`.

## Convenções

- **Todo o código em inglês**: arquivos, funções, variáveis, nomes de tool,
  valores de status, chaves de cenário, nomes de evento. Em português apenas o
  texto que uma pessoa lê (interface e descrições de papel nos cenários) e a
  documentação.
- Documentação, ADRs, backlog e mensagens de commit em português.

## Fluxo de trabalho

- TDD: teste que falha → rodar e ver falhar → implementação mínima → rodar e ver
  passar → commit.
- Uma tarefa do backlog por vez; os passos do arquivo da tarefa são o roteiro.
- **Decisão arquitetural vira ADR antes do código.** Use `/adr`. ADRs são
  imutáveis: um ADR errado se supersede, não se reescreve.
```

- [ ] **Passo 2: escrever o hook de formatação**

`.claude/hooks/format-python.sh`:

```bash
#!/usr/bin/env bash
# Formata e corrige o arquivo Python que acabou de ser editado.
set -euo pipefail

file=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')

[[ "$file" == *.py ]] || exit 0
[[ -f "$file" ]] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"
uv run ruff format "$file" >/dev/null 2>&1 || true
uv run ruff check --fix "$file" >/dev/null 2>&1 || true
```

```bash
chmod +x .claude/hooks/format-python.sh
```

- [ ] **Passo 3: escrever o `.claude/settings.json`**

```json
{
  "permissions": {
    "allow": [
      "Bash(make:*)",
      "Bash(uv run pytest:*)",
      "Bash(uv run ruff:*)",
      "Bash(uv run lint-imports:*)",
      "Bash(docker compose ps:*)",
      "Bash(docker compose logs:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/format-python.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Passo 4: escrever o comando `/tarefa`**

`.claude/commands/tarefa.md`:

```markdown
---
description: Carrega uma tarefa do backlog com todo o contexto para implementá-la
---

Implemente a tarefa do backlog em: $ARGUMENTS

Contexto obrigatório antes de escrever qualquer código:

- Leia o arquivo da tarefa por inteiro, incluindo "Interfaces" e "Pronto quando".
- Leia os ADRs que a tarefa referencia. Eles dizem por que o desenho é assim;
  se você discordar de um, pare e me diga — não implemente contra ele em
  silêncio.
- Restrições globais do backlog: @docs/features/README.md

Siga os passos da tarefa na ordem. TDD de verdade: escreva o teste, rode e
**veja falhar** antes de implementar. Não pule o passo de ver falhar — teste que
nunca falhou não prova nada.

Ao final, rode `make test` e `make lint` e me mostre a saída antes de afirmar
que terminou.

Se durante a implementação você precisar tomar uma decisão arquitetural que a
tarefa não previu, pare e me avise: ela vira ADR antes do código.
```

- [ ] **Passo 5: escrever o comando `/adr`**

`.claude/commands/adr.md`:

```markdown
---
description: Cria o próximo ADR numerado no formato MADR enxuto
allowed-tools: Bash(ls:*), Write
---

ADRs existentes:

!`ls docs/adr/ | grep -E '^[0-9]{4}-' | sort | tail -5`

Crie o **próximo** número sequencial de quatro dígitos, em
`docs/adr/NNNN-<slug-em-portugues>.md`, para a decisão: $ARGUMENTS

Formato:

- Título `# ADR NNNN — <decisão em uma frase afirmativa>`
- `- Status: aceito` e `- Data: <hoje, YYYY-MM-DD>`
- `## Contexto` — a pressão que força a escolha, não a escolha
- `## Decisão` — o que foi decidido, na voz ativa
- `## Consequências` — o que melhora e o que piora; sempre inclua o custo
- `## Alternativas descartadas` — cada uma com o motivo real da rejeição

Regras: ADRs são imutáveis. Se esta decisão substitui uma anterior, marque a
anterior como `superado por NNNN` e explique o que mudou desde então. Ao
terminar, adicione a linha correspondente na tabela de `docs/adr/README.md`.
```

- [ ] **Passo 6: verificar o hook**

Peça ao Claude para editar qualquer arquivo `.py` com formatação ruim de
propósito (espaçamento errado, import fora de ordem) e confirme que o arquivo
volta formatado sem ninguém pedir.

- [ ] **Passo 7: verificar os comandos**

Rode `/adr teste de fumaça do comando` e confirme que o arquivo nasce com o
número certo. Apague-o depois — ADR de teste não vai para o histórico.

Rode `/tarefa docs/features/01-fundacao/01-esqueleto-python.md` e confirme que o
Claude lê a tarefa, os ADRs referenciados e as restrições globais antes de agir.

- [ ] **Passo 8: commit**

```bash
git add CLAUDE.md .claude
git commit -m "chore: setup versionável do Claude com hook de formatação e comandos"
```

## Pronto quando

- `CLAUDE.md` cabe em uma tela e meia e não repete o que está no spec.
- Editar um `.py` pelo Claude dispara `ruff format` automaticamente.
- `/adr <título>` cria o próximo número correto e atualiza o índice.
- `/tarefa <caminho>` carrega tarefa + ADRs + restrições globais.
- `.claude/settings.local.json` e `.env` continuam fora do git.
