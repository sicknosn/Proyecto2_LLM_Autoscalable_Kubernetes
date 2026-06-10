from fastapi import FastAPI, HTTPException, Request
import httpx, os
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="LLM API Gateway")
Instrumentator().instrument(app).expose(app)

VLLM_URL = os.getenv("VLLM_ENDPOINT_URL", "http://vllm-server:8000")
API_KEY  = os.getenv("API_KEY_SECRET", "")

def classify(messages):
    text = " ".join(m.get("content","") for m in messages)
    if len(text.split()) < 60 and not any(k in text.lower()
       for k in ["codigo","code","funcion","implement","debug","explain"]):
        return "fast"
    return "full"

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/v1/chat/completions")
async def chat(request: Request):
    if API_KEY:
        auth = request.headers.get("Authorization","")
        if auth != f"Bearer {API_KEY}":
            raise HTTPException(status_code=401, detail="Unauthorized")
    body = await request.json()
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(f"{VLLM_URL}/v1/chat/completions", json=body)
    return resp.json()
