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
