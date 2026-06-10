# scripts\05_build_push.ps1

# ─────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────
$ACR_NAME = "acrllmproyecto"
$SUB_ID   = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"

# ─────────────────────────────────────────────────────────
# LOGIN ACR
# ─────────────────────────────────────────────────────────
Write-Host "=== Login ACR ===" -ForegroundColor Cyan
az account set --subscription $SUB_ID
az acr login --name $ACR_NAME

# ─────────────────────────────────────────────────────────
# CREAR ARCHIVOS DE CODIGO
# ─────────────────────────────────────────────────────────
Write-Host "=== Creando archivos de codigo ===" -ForegroundColor Cyan

# entrypoint.sh
@"
#!/bin/bash
set -e
exec python -m vllm.entrypoints.openai.api_server \
  --model "`${MODEL_NAME:-TheBloke/Llama-3-8B-Instruct-AWQ}" \
  --quantization awq \
  --dtype float16 \
  --max-model-len "`${MAX_MODEL_LEN:-8192}" \
  --gpu-memory-utilization "`${GPU_MEMORY_UTILIZATION:-0.85}" \
  --max-num-seqs "`${MAX_NUM_SEQS:-128}" \
  --max-num-batched-tokens 8192 \
  --block-size 16 \
  --swap-space 4 \
  --enable-chunked-prefill \
  --port 8000 \
  --host 0.0.0.0
"@ | Out-File -FilePath "docker\entrypoint.sh" -Encoding UTF8 -NoNewline

# Dockerfile vLLM
@"
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3-pip git curl \
    && rm -rf /var/lib/apt/lists/*

RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip && pip install \
    vllm==0.4.3 \
    torch==2.3.0+cu121 \
    transformers==4.41.0 \
    accelerate autoawq huggingface_hub

FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04 AS runtime
ENV PYTHONUNBUFFERED=1 PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 libgomp1 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv

RUN groupadd --gid 1000 vllmuser && \
    useradd --uid 1000 --gid 1000 --no-create-home vllmuser

WORKDIR /app
COPY docker/entrypoint.sh ./
RUN chmod +x entrypoint.sh

USER vllmuser
EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]
"@ | Out-File -FilePath "docker\Dockerfile.vllm" -Encoding UTF8

# requirements.txt
@"
fastapi==0.111.0
uvicorn[standard]==0.30.0
httpx==0.27.0
pydantic==2.7.0
prometheus-fastapi-instrumentator==7.0.0
"@ | Out-File -FilePath "app\requirements.txt" -Encoding UTF8

# main.py
@"
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
"@ | Out-File -FilePath "app\main.py" -Encoding UTF8

# Dockerfile Gateway
@"
FROM python:3.11-slim AS deps
ENV PIP_NO_CACHE_DIR=1
WORKDIR /build
COPY app/requirements.txt .
RUN pip install --upgrade pip && pip install --prefix=/install -r requirements.txt

FROM python:3.11-slim AS final
ENV PYTHONUNBUFFERED=1 PATH="/install/bin:$PATH" \
    PYTHONPATH="/install/lib/python3.11/site-packages"
COPY --from=deps /install /install
RUN groupadd --gid 1000 appuser && useradd --uid 1000 --gid 1000 --no-create-home appuser
WORKDIR /app
COPY --chown=appuser:appuser app/ ./
USER appuser
EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]
"@ | Out-File -FilePath "docker\Dockerfile.gateway" -Encoding UTF8

Write-Host "Archivos de codigo creados." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# BUILD GATEWAY (rapido ~3 min)
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Build API Gateway (~3 min) ===" -ForegroundColor Cyan
docker build `
  -f docker\Dockerfile.gateway `
  -t "$ACR_NAME.azurecr.io/llm-project/api-gateway:v1.0.0" `
  -t "$ACR_NAME.azurecr.io/llm-project/api-gateway:latest" `
  .

Write-Host "Gateway build listo." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# PUSH GATEWAY
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Push Gateway a ACR ===" -ForegroundColor Cyan
docker push "$ACR_NAME.azurecr.io/llm-project/api-gateway:v1.0.0"
docker push "$ACR_NAME.azurecr.io/llm-project/api-gateway:latest"
Write-Host "Gateway en ACR." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# BUILD vLLM (pesado ~20-30 min por CUDA)
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Build vLLM server (~20-30 min por imagen CUDA) ===" -ForegroundColor Yellow
Write-Host "No cierres esta ventana..." -ForegroundColor Yellow
docker build `
  -f docker\Dockerfile.vllm `
  -t "$ACR_NAME.azurecr.io/llm-project/vllm-server:v1.0.0" `
  -t "$ACR_NAME.azurecr.io/llm-project/vllm-server:latest" `
  .

Write-Host "vLLM build listo." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# PUSH vLLM
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Push vLLM a ACR ===" -ForegroundColor Cyan
docker push "$ACR_NAME.azurecr.io/llm-project/vllm-server:v1.0.0"
docker push "$ACR_NAME.azurecr.io/llm-project/vllm-server:latest"
Write-Host "vLLM en ACR." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# VERIFICAR ACR
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Imagenes en ACR ===" -ForegroundColor Cyan
az acr repository list --name $ACR_NAME --output table

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  FASE 6 COMPLETADA - IMAGENES EN ACR" -ForegroundColor Green
Write-Host "================================================"
Write-Host "  Siguiente: los pods del cluster levantaran"
Write-Host "  automaticamente al detectar las imagenes."
Write-Host ""
Write-Host "  Monitorea con:"
Write-Host "  kubectl get pods -n llm-serving --watch"
Write-Host "================================================"