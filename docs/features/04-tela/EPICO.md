# Épico 04 — Tela

## Objetivo

Quatro colunas em Nuxt 4: três chats e o painel que torna o raciocínio do agente
observável.

## Por que existe

O critério de sucesso da v1 (spec §2) inclui "ler no painel, depois do fato, por
que o agente fez o que fez". Sem o painel o projeto vira um chatbot com três
janelas, e nenhuma das perguntas interessantes tem resposta.

## Tarefas previstas

Detalhadas quando o épico 03 fechar.

1. Nuxt 4 no Compose, cliente WebSocket e store de sessão (com Vitest)
2. Três colunas de chat, com indicador de processamento por canal
3. Painel: quadro de fatos como tabela viva, cor por status
4. Painel: trilha, um bloco expansível por ciclo com gatilho, ações e diff
5. Controles de topo — seletor de cenário, nova sessão, contador de ciclos
   autônomos consecutivos, botão de parar o agente — e colapso em abas na tela
   estreita

## Critério de pronto

- Os três cenários do critério de sucesso da v1 são executáveis pela tela, do
  começo ao fim, incluindo a quebra no meio.
- O contador de ciclos autônomos e o estouro do teto aparecem na tela, em
  vermelho.
- Em largura de celular, as quatro colunas viram abas sem perder nada.
