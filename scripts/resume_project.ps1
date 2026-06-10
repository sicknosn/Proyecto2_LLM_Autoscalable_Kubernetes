# scripts\resume_project.ps1

$RG      = "rg-llm-project"
$CLUSTER = "aks-llm-cluster"
$SUB_ID  = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"
$TENANT  = "ea671317-5e0d-4e35-8d02-6a7c57afb569"

Write-Host "=== Reactivando proyecto LLM ===" -ForegroundColor Cyan

# Login con MFA
az login --tenant $TENANT
az account set --subscription $SUB_ID

# Iniciar cluster
Write-Host "=== Iniciando cluster AKS (~3 min) ===" -ForegroundColor Cyan
az aks start `
  --resource-group $RG `
  --name $CLUSTER

# Reconectar kubectl
az aks get-credentials `
  --resource-group $RG `
  --name $CLUSTER `
  --overwrite-existing

# Login ACR
az acr login --name acrllmproyecto

# Ver estado actual
Write-Host "=== Estado del cluster ===" -ForegroundColor Cyan
kubectl get nodes
kubectl get pods -n llm-serving

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Proyecto reactivado." -ForegroundColor Green
Write-Host "  Siguiente paso pendiente:" -ForegroundColor Green
Write-Host "  Esperar aprobacion de cuota GPU y ejecutar:" -ForegroundColor Green
Write-Host "  az aks nodepool add (GPU T4 spot)" -ForegroundColor Green
Write-Host "================================================"