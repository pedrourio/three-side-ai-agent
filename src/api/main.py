from fastapi import FastAPI

app = FastAPI(title="three-side-ai-agent")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
