# three-side-ai-agent — Design da v1

Data: 2026-09-19
Status: aprovado em brainstorming, pendente de revisão final

## 1. O problema

Um agente de IA conversa simultaneamente com três pessoas diferentes que,
juntas, precisam chegar a um único resultado. Cada uma detém uma parte da
informação, nenhuma fala com as outras, e o que uma diz pode invalidar o que
outra já confirmou.

Cenário de referência: uma secretária de empresa (S1) precisa agendar consulta
para um colaborador; a secretária da clínica (S2) é a única que conhece a
agenda; o paciente (P) é quem pode ou não aceitar o horário. O agente recebe o
pedido de S1, descobre a disponibilidade com S2, confirma com P — e precisa
sobreviver a P pedindo outro horário depois de S2 já ter reservado, ou a S1
cancelando tudo no meio.

O desafio técnico não é conversar; é **coordenar estado compartilhado entre três
conversas independentes, sob efeitos cruzados, sem perder nem inventar
confirmações**.

## 2. Objetivo da v1 e critério de sucesso

Uma demonstração ao vivo: uma tela com três chats lado a lado mais um painel de
estado. O desenvolvedor interpreta S1, S2 e P manualmente e observa o agente
coordenar.

A v1 está pronta quando, no cenário de agendamento, o desenvolvedor consegue:

1. levar um agendamento do pedido inicial à confirmação nos três lados;
2. quebrar o fluxo no meio (P pede outro horário após S2 confirmar; S1 cancela)
   e ver o agente detectar, propagar e renegociar;
3. ler no painel, depois do fato, **por que** o agente fez o que fez.

## 3. Fora de escopo da v1

Decidido explicitamente para depois: personas simuladas por LLM (S1, S2 e P são
sempre o desenvolvedor), suíte automatizada de cenários com placar,
autenticação, multiusuário, deploy fora do Compose, mais de um agente.

## 4. Arquitetura

```
  navegador
      │  WebSocket (1 por sessão)
      ▼
 ┌──────────────────────────────┐        ┌──────────────┐
 │ api/  (FastAPI)              │        │ litellm      │
 │  sessão = fila + 1 worker    │ HTTP   │ proxy        │──▶ Gemini
 │  timers (asyncio)            │───────▶│ OpenAI-compat│──▶ Groq
 │      │                       │        │ + fallback   │──▶ OpenRouter
 │      ▼                       │        └──────────────┘
 │ core/ (Python puro)          │
 │  ciclo, estado, tools,       │
 │  cenário                     │
 └──────────────┬───────────────┘
                │ SessionStore
                ▼
        ┌──────────────┐
        │ postgres     │  sessions(id, state JSONB, updated_at)
        │ (volume)     │
        └──────────────┘
```

Quatro peças no Docker Compose:

**`core/`** — pacote Python do agente: grafo LangGraph, objeto de estado, tools,
carregador de cenário, cliente de LLM. **Não importa FastAPI e não conhece
WebSocket.** Essa fronteira é o que permite rodar o agente por script de
terminal, testá-lo sem servidor e, no futuro, plugar personas simuladas sem
tocar no núcleo. É verificada por lint (import-linter), não por disciplina.

**`api/`** (FastAPI) — dono das sessões. Cada sessão tem uma `asyncio.Queue` e
**um único worker**. Mensagens de S1, S2, P e eventos de timer entram todos na
mesma fila e são processados um por vez: duas mensagens simultâneas viram duas
entradas ordenadas, nunca dois ticks pisando no mesmo estado. Expõe um WebSocket
por sessão e REST para criar/listar sessões e cenários.

**`litellm`** — proxy OpenAI-compatible. O `core` conhece apenas um `base_url` e
um nome lógico de modelo (`primary-agent`); qual provedor atende é YAML.

**`web/`** (Nuxt 4) — três colunas de chat e uma de estado/trilha, alimentadas
por um WebSocket só.

**Persistência**: Postgres em container com volume, uma tabela
`sessions(id, state JSONB, updated_at)` atrás do Protocol `SessionStore`
([ADR 0009](../../adr/0009-postgres-como-banco-da-sessao.md)). Recarregar a
página continua a sessão, e a trilha fica gravada — em `JSONB`, portanto
consultável por SQL, que é o que torna barato analisar o comportamento do agente
depois da demo. Sem Redis nem Celery: a fila é `asyncio` e os timers são tasks
`asyncio` que enfileiram eventos. Se algum dia houver mais de um worker, a fila
é o ponto de troca.

## 5. O núcleo do agente

### 5.1 Estado

Duas metades:

- **Conversas** — histórico de mensagens por canal (`s1`, `s2`, `p`).
- **Quadro de fatos** — representação estruturada do objetivo. Cada fato tem
  `name`, `value`, `source` (quem disse), `status` e `confirmed_by` (conjunto de
  canais).

Status possíveis de um fato: `proposed`, `confirmed`, `needs_reconfirmation`,
`invalidated`.

O quadro de fatos é o que o painel desenha e o que os testes afirmam.

### 5.2 Tools do agente

| Tool | Efeito |
|------|--------|
| `send(channel, text)` | emite mensagem para um dos três chats |
| `record_fact(name, value, source)` | cria/atualiza um fato como `proposed` |
| `confirm_fact(name, channel)` | adiciona `channel` a `confirmed_by` |
| `invalidate_fact(name, reason)` | marca `invalidated` e dispara propagação |
| `schedule_followup(when, reason)` | cria timer que reacorda o agente |
| `cancel_followup(id)` | remove timer pendente |
| `finish(outcome)` | encerra a sessão com desfecho registrado |

Ao fim de cada ciclo o agente declara `continue` ou `sleep`.

### 5.3 O tick

Entra um evento — mensagem humana ou timer vencido. O agente vê o estado inteiro
(três conversas + quadro de fatos + cenário), emite quantas ações quiser
(inclusive falar com os três no mesmo ciclo) e declara se ainda tem trabalho.

"Continuar" o faz rodar de novo sem esperar ninguém. Um **teto de 5 ciclos
consecutivos sem entrada humana** o força a dormir; o painel marca o
estouro em vermelho. Agente em laço é bug a observar, não a esconder.

### 5.4 Conflito: código propaga, agente julga

Quando um fato muda de valor ou é invalidado, o **código** propaga a mecânica:
todo fato que declara dependência dele volta a `needs_reconfirmation`, e as
confirmações caem. As dependências são declaradas no cenário.

O **agente** decide o que fazer a respeito: quem avisar primeiro, se cancela com
S2 antes de oferecer alternativa a P, se negocia ou desiste.

Essa divisão é deliberada e é o coração do projeto: a contabilidade é
determinística (o agente não pode esquecer silenciosamente uma confirmação) e o
julgamento continua sendo dele (é o que queremos observar).

### 5.5 Falhas

- **Tool call malformada** — volta ao modelo com a mensagem de erro; duas
  tentativas; depois o ciclo aborta e o aborto vira evento na trilha.
- **Provedor indisponível** — fallback em cascata do LiteLLM; se todos falharem,
  a sessão fica visivelmente em erro, com o evento na trilha.
- **Teto de ciclos estourado** — sessão permanece viva e marcada como travada.
  Nunca morre em silêncio.

### 5.6 Trilha

Cada ciclo grava: o que o acordou, as ações emitidas e o diff do quadro de
fatos. A trilha é persistida junto do estado.

## 6. Cenário como dado

Um YAML validado por Pydantic na carga — cenário quebrado falha ao subir, não no
meio da demo.

As **chaves** são em inglês; o **conteúdo** é o texto que vai para o prompt e
que o desenvolvedor lê na tela, portanto em português.

```yaml
id: appointment-scheduling
name: Agendamento de consulta
goal: >
  Agendar uma consulta para o colaborador indicado por S1, em horário que
  exista na agenda de S2 e que P aceite.

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

A v1 entrega este cenário. Um segundo cenário de domínio distinto (negociação de
entrega entre comprador, fornecedor e transportadora) entra como tarefa tardia
do backlog, com propósito específico: provar que o núcleo não absorveu o domínio
médico sem ninguém perceber.

## 7. Interface

### 7.1 Tela

Quatro colunas. Três de chat — histórico, campo de envio, indicador de que o
agente está processando aquele canal. A quarta é o painel:

- **em cima**: quadro de fatos como tabela viva, cor por status;
- **embaixo**: trilha, um bloco expansível por ciclo com gatilho, ações emitidas
  e diff dos fatos.

No topo: seletor de cenário, botão de nova sessão, contador de ciclos autônomos
consecutivos e **botão de parar o agente** — o teto de 5 é o freio automático; o
botão é o freio de mão para quando o desenvolvedor estiver provocando de
propósito.

Em tela estreita, as quatro colunas viram abas.

### 7.2 Transporte

Um WebSocket por sessão, eventos tipados:

- entrando: `human_message`
- saindo: `agent_message`, `facts_changed`, `cycle`, `status`

Os tipos TypeScript são **gerados** a partir dos modelos Pydantic (JSON Schema →
`json-schema-to-typescript`, via `make types`). O front nunca mantém uma cópia
manual dos contratos.

## 8. Estratégia de teste

A fronteira da seção 4 é o que torna isso possível: como `core/` não conhece a
web nem o provedor, os testes injetam um **modelo falso** que devolve sequência
roteirizada de tool calls. O teste vira determinístico e afirma sobre o que
importa.

Onde um store for necessário, o `make test` usa `InMemorySessionStore`. Os
testes do SQL de verdade vivem em `make test-db`, marcados `-m db`, e exigem o
Compose de pé — consequência aceita no
[ADR 0009](../../adr/0009-postgres-como-banco-da-sessao.md).

Cobertura obrigatória em `make test` (sem rede, sem chave de API, segundos):

- propagação de invalidação (S2 confirma 14h, P pede 16h → confirmação de S2 cai
  para `needs_reconfirmation`);
- teto de ciclos autônomos;
- follow-up disparando no tempo, com relógio falso;
- tool call malformada e o caminho de retry/aborto;
- validação de cenário (YAML inválido falha na carga);
- contrato dos eventos do WebSocket.

Front: Vitest no store de sessão. Sem e2e na v1.

Contra LLM real roda uma suíte pequena, marcada e **fora** do `make test`: ela
verifica que o agente *consegue*, não que o código está correto. Rodar
manualmente, porque consome cota de provedor gratuito.

## 9. Setup versionável do Claude

Commitado:

- **`CLAUDE.md`** na raiz, curto de propósito: o que é o projeto em duas linhas,
  os comandos (`make up`, `make test`, `make lint`, `make types`), as regras de
  fronteira (`core/` não importa `api/` nem `fastapi`; tipos do front são
  gerados), o fluxo (TDD, backlog em `docs/features/`) e a regra dura: **decisão
  arquitetural vira ADR antes do código**. O resto fica em `docs/` e é
  referenciado, não colado.
- **`.claude/settings.json`** — permissões compartilhadas (liberar `make`,
  `pytest`, `docker compose`, `git status/diff`; negar leitura de `.env`) e hook
  `PostToolUse` rodando `ruff format` e `ruff check --fix` no arquivo Python
  recém-editado.
- **`.claude/commands/tarefa.md`** — carrega uma tarefa do backlog junto do spec
  e dos ADRs relevantes.
- **`.claude/commands/adr.md`** — cria o próximo ADR numerado no formato MADR.

Não commitado: `.claude/settings.local.json`, `.env`.

Subagentes e skills de projeto ficam de fora até existir repetição que os
justifique.

## 10. Estrutura de diretórios

```
.
├── CLAUDE.md
├── Makefile
├── compose.yaml
├── .env.example
├── .claude/
│   ├── settings.json
│   └── commands/{tarefa.md,adr.md}
├── docs/
│   ├── adr/                  # MADR enxuto, numerado, imutável
│   ├── features/             # backlog: 1 md por feature; épico = subpasta
│   └── superpowers/specs/
├── src/
│   ├── core/                 # pacote puro: graph, state, facts, tools,
│   │                         #   scenario, llm
│   └── api/                  # main, session (fila+worker), ws, events
├── tests/
├── web/                      # Nuxt 4
├── scenarios/appointment-scheduling.yaml
└── litellm/config.yaml

```

## 11. Convenções

- **Idioma: todo o código em inglês, sem exceção.** Nomes de arquivo, módulos,
  classes, funções, variáveis, nomes de tool expostos ao modelo, valores de
  status, chaves de cenário, nomes de evento do WebSocket.
  Em português ficam apenas duas coisas: o **texto que uma pessoa lê** — rótulos
  e mensagens da interface, e as descrições de papel dentro dos cenários, que
  são conteúdo de prompt para personas que conversam em português — e a
  **documentação**: spec, ADRs e backlog.
- Python gerenciado por `uv`; lint e format por `ruff`; fronteira de import por
  `import-linter`; tipos por Pydantic v2.
- `Makefile` é a interface única: `up`, `down`, `test`, `test-db`, `lint`,
  `types`, `logs`, `ping`.
- ADRs são imutáveis: ADR errado não se apaga, se supersede.

## 12. Processo de trabalho

Esta sessão do Claude atua como PO: produz o spec e quebra o trabalho em
tarefas. O desenvolvedor decide, tarefa a tarefa, se implementa à mão ou com
assistência.

Cada tarefa tem escopo mínimo e **verificável de ponta a ponta** — uma feature
que roda e se testa, não "criar o model X". Cada markdown de tarefa carrega
contexto suficiente para alguém que não participou desta conversa.

Backlog em `docs/features/`: um arquivo por feature; épico vira subpasta com um
markdown do épico (objetivo, ordem das tarefas, critério de pronto) e os demais
arquivos como tarefas.

## 13. Riscos conhecidos

- **Prompt único crescendo** — três conversas num contexto só eventualmente
  sufoca. Mitigação prevista: resumo por canal quando passar de um limiar. Se
  virar problema estrutural, a saída é o desenho de orquestrador + sub-agentes
  (registrado como alternativa descartada no ADR 0002).
- **Cota de provedor gratuito** — limites de taxa podem interromper uma demo. O
  fallback em cascata do LiteLLM mitiga; a suíte determinística garante que
  desenvolvimento não depende de cota.
- **Modelos gratuitos e tool calling** — nem todo modelo gratuito segue tool
  schema de forma confiável. O caminho de retry cobre o caso, e a troca de
  modelo é uma linha de YAML.
