# scripts\03_gpu_operator.ps1

# ─────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────
$RG        = "rg-llm-project"
$CLUSTER   = "aks-llm-cluster"
$SUB_ID    = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"

# ─────────────────────────────────────────────────────────
# VERIFICAR SESION Y CONEXION
# ─────────────────────────────────────────────────────────
Write-Host "=== Verificando sesion Azure ===" -ForegroundColor Cyan
az account set --subscription $SUB_ID
az aks get-credentials `
  --resource-group $RG `
  --name $CLUSTER `
  --overwrite-existing

Write-Host "=== Nodos actuales ===" -ForegroundColor Cyan
kubectl get nodes -o wide

# ─────────────────────────────────────────────────────────
# INSTALAR NVIDIA GPU OPERATOR
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Agregando repositorio Helm de NVIDIA ===" -ForegroundColor Cyan
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
Write-Host "Repositorio agregado." -ForegroundColor Green

Write-Host ""
Write-Host "=== Instalando GPU Operator (~3-5 min) ===" -ForegroundColor Cyan
helm install gpu-operator nvidia/gpu-operator `
  --namespace gpu-operator `
  --create-namespace `
  --set driver.enabled=true `
  --set toolkit.enabled=true `
  --set devicePlugin.enabled=true `
  --set dcgmExporter.enabled=true `
  --set dcgmExporter.serviceMonitor.enabled=false

Write-Host "GPU Operator instalado." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# INSTALAR METRICS SERVER (necesario para HPA)
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Instalando Metrics Server ===" -ForegroundColor Cyan
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm install metrics-server metrics-server/metrics-server `
  --namespace kube-system `
  --set args[0]="--kubelet-insecure-tls"

Write-Host "Metrics Server instalado." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# VERIFICAR PODS
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Esperando 60 segundos para que los pods arranquen ===" -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Host ""
Write-Host "=== Pods GPU Operator ===" -ForegroundColor Cyan
kubectl get pods -n gpu-operator

Write-Host ""
Write-Host "=== Pods Metrics Server ===" -ForegroundColor Cyan
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

Write-Host ""
Write-Host "=== Verificando GPU disponible en nodos ===" -ForegroundColor Cyan
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable."nvidia\.com/gpu"

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  FASE 4 COMPLETADA - GPU OPERATOR INSTALADO" -ForegroundColor Green
Write-Host "================================================"
Write-Host "  Si ves '1' en la columna GPU del nodo gpunodes,"
Write-Host "  el cluster esta listo para servir Llama 3 8B."
Write-Host "================================================"