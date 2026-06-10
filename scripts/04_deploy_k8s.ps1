# scripts\04_deploy_k8s.ps1

# ─────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────
$SUB_ID   = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"
$RG       = "rg-llm-project"
$CLUSTER  = "aks-llm-cluster"
$ACR_NAME = "acrllmproyecto"

# ─── CAMBIA ESTO: tu token de HuggingFace ────────────────
# Obtén el tuyo en https://huggingface.co/settings/tokens
$HF_TOKEN = "hf_xxxxxxxxxxxxxxxxx"

# ─── CAMBIA ESTO: una clave cualquiera para tu API ───────
$API_KEY  = "mi-api-key-proyecto2"
# ─────────────────────────────────────────────────────────

Write-Host "=== Verificando sesion ===" -ForegroundColor Cyan
az account set --subscription $SUB_ID
az aks get-credentials --resource-group $RG --name $CLUSTER --overwrite-existing

# ─────────────────────────────────────────────────────────
# CREAR ARCHIVOS YAML
# ─────────────────────────────────────────────────────────
Write-Host "=== Creando manifiestos YAML ===" -ForegroundColor Cyan

# Namespace
@"
apiVersion: v1
kind: Namespace
metadata:
  name: llm-serving
  labels:
    app.kubernetes.io/part-of: llm-project
"@ | Out-File -FilePath "k8s\namespace.yaml" -Encoding UTF8

# ConfigMap
@"
apiVersion: v1
kind: ConfigMap
metadata:
  name: vllm-config
  namespace: llm-serving
data:
  MODEL_NAME: "TheBloke/Llama-3-8B-Instruct-AWQ"
  MAX_MODEL_LEN: "8192"
  GPU_MEMORY_UTILIZATION: "0.85"
  MAX_NUM_SEQS: "128"
  MAX_NUM_BATCHED_TOKENS: "8192"
  TENSOR_PARALLEL_SIZE: "1"
"@ | Out-File -FilePath "k8s\configmap.yaml" -Encoding UTF8

# Services
@"
apiVersion: v1
kind: Service
metadata:
  name: vllm-server
  namespace: llm-serving
  labels:
    app: vllm-server
spec:
  selector:
    app: vllm-server
  ports:
    - name: http
      port: 8000
      targetPort: 8000
      protocol: TCP
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: llm-serving
  labels:
    app: api-gateway
spec:
  selector:
    app: api-gateway
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
"@ | Out-File -FilePath "k8s\services.yaml" -Encoding UTF8

# Deployment vLLM
@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-server
  namespace: llm-serving
  labels:
    app: vllm-server
    version: v1.0.0
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vllm-server
  template:
    metadata:
      labels:
        app: vllm-server
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
      nodeSelector:
        accelerator: nvidia-tesla-t4
      tolerations:
        - key: "sku"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
        - key: "kubernetes.azure.com/scalesetpriority"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - vllm-server
              topologyKey: kubernetes.io/hostname
      initContainers:
        - name: model-downloader
          image: python:3.11-slim
          command:
            - sh
            - -c
            - |
              pip install -q huggingface_hub &&
              python -c "
              from huggingface_hub import snapshot_download
              import os
              snapshot_download(
                repo_id=os.environ['MODEL_NAME'],
                local_dir='/models/llama-3-8b-awq',
                token=os.environ['HF_TOKEN']
              )"
          env:
            - name: MODEL_NAME
              valueFrom:
                configMapKeyRef:
                  name: vllm-config
                  key: MODEL_NAME
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: llm-secrets
                  key: HF_TOKEN
          volumeMounts:
            - name: model-storage
              mountPath: /models
          resources:
            requests:
              cpu: "1"
              memory: "4Gi"
            limits:
              cpu: "2"
              memory: "8Gi"
      containers:
        - name: vllm-server
          image: ${ACR_NAME}.azurecr.io/llm-project/vllm-server:v1.0.0
          imagePullPolicy: Always
          ports:
            - containerPort: 8000
              name: http
          envFrom:
            - configMapRef:
                name: vllm-config
          env:
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: llm-secrets
                  key: HF_TOKEN
          resources:
            requests:
              cpu: "4"
              memory: "12Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "4"
              memory: "14Gi"
              nvidia.com/gpu: "1"
          startupProbe:
            httpGet:
              path: /health
              port: 8000
            failureThreshold: 40
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /v1/models
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 120
            periodSeconds: 30
            failureThreshold: 3
          volumeMounts:
            - name: model-storage
              mountPath: /models
      volumes:
        - name: model-storage
          emptyDir:
            sizeLimit: 15Gi
"@ -replace '\${ACR_NAME}', $ACR_NAME | Out-File -FilePath "k8s\deployment-vllm.yaml" -Encoding UTF8

# Deployment Gateway
@"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: llm-serving
  labels:
    app: api-gateway
    version: v1.0.0
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - api-gateway
                topologyKey: kubernetes.io/hostname
      containers:
        - name: api-gateway
          image: ${ACR_NAME}.azurecr.io/llm-project/api-gateway:v1.0.0
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: VLLM_ENDPOINT_URL
              value: "http://vllm-server.llm-serving.svc.cluster.local:8000"
            - name: API_KEY_SECRET
              valueFrom:
                secretKeyRef:
                  name: llm-secrets
                  key: API_KEY_SECRET
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 30
"@ -replace '\${ACR_NAME}', $ACR_NAME | Out-File -FilePath "k8s\deployment-gateway.yaml" -Encoding UTF8

# HPA
@"
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-hpa
  namespace: llm-serving
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm-server
  minReplicas: 1
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
    scaleDown:
      stabilizationWindowSeconds: 300
"@ | Out-File -FilePath "k8s\hpa.yaml" -Encoding UTF8

Write-Host "Archivos YAML creados." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# APLICAR MANIFIESTOS
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Aplicando manifiestos al cluster ===" -ForegroundColor Cyan

kubectl apply -f k8s\namespace.yaml
Write-Host "Namespace listo." -ForegroundColor Green

kubectl create secret generic llm-secrets `
  --namespace llm-serving `
  --from-literal=HF_TOKEN="$HF_TOKEN" `
  --from-literal=API_KEY_SECRET="$API_KEY" `
  --dry-run=client -o yaml | kubectl apply -f -
Write-Host "Secrets aplicados." -ForegroundColor Green

kubectl apply -f k8s\configmap.yaml
Write-Host "ConfigMap listo." -ForegroundColor Green

kubectl apply -f k8s\services.yaml
Write-Host "Services listos." -ForegroundColor Green

kubectl apply -f k8s\deployment-gateway.yaml
Write-Host "Deployment Gateway aplicado." -ForegroundColor Green

kubectl apply -f k8s\deployment-vllm.yaml
Write-Host "Deployment vLLM aplicado." -ForegroundColor Green

kubectl apply -f k8s\hpa.yaml
Write-Host "HPA aplicado." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# ESTADO INICIAL
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Estado inicial de pods ===" -ForegroundColor Cyan
kubectl get pods -n llm-serving

Write-Host ""
Write-Host "=== Estado de nodos (el GPU aparecera en ~5 min) ===" -ForegroundColor Cyan
kubectl get nodes

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  FASE 5 COMPLETADA - MANIFIESTOS APLICADOS" -ForegroundColor Green
Write-Host "================================================"
Write-Host "  El pod vLLM quedara Pending hasta que el"
Write-Host "  Cluster Autoscaler aprovisione el nodo GPU T4."
Write-Host "  Esto tarda entre 3 y 8 minutos."
Write-Host ""
Write-Host "  Monitorea con:"
Write-Host "  kubectl get pods -n llm-serving --watch"
Write-Host "================================================"