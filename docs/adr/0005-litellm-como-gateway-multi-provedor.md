# ADR 0005 — LiteLLM Proxy como gateway multi-provedor

- Status: aceito
- Data: 2026-09-19

## Contexto

Projeto pessoal, sem orçamento: os modelos precisam vir de camadas gratuitas ou
de cota cedida para teste. Camadas gratuitas têm limite de taxa e mudam de
condição sem aviso, então depender de um provedor único é frágil. O núcleo não
deveria conhecer nenhum deles.

## Decisão

Um container `litellm` no Compose, falando protocolo OpenAI-compatible. O `core`
conhece apenas um `base_url` e um nome lógico de modelo (`agente-principal`).
Provedores (Gemini, Groq, OpenRouter e outros) e a ordem de fallback vivem em
`litellm/config.yaml`.

## Consequências

- Trocar de modelo ou provedor é editar YAML; nenhum código muda.
- Fallback em cascata entre provedores distintos quando um estoura cota.
- Um ponto único para observar custo e latência.
- Custo: mais um container e um arquivo de configuração para manter.

## Alternativas descartadas

- **OpenRouter direto** — uma chave, centenas de modelos incluindo gratuitos,
  zero infra extra; mas é um intermediário único, e um problema nele derruba
  tudo sem rota alternativa. Continua sendo um dos provedores *atrás* do
  LiteLLM.
- **Camada de abstração própria sobre os SDKs** — controle total e bom
  exercício, mas seria manter à mão exatamente o que o LiteLLM já resolve, em um
  projeto cujo desafio é outro.
