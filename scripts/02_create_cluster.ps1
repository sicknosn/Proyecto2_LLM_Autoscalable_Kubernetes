# scripts\02_create_cluster.ps1

# ─────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────
$RG        = "rg-llm-project"
$LOCATION  = "eastus"
$ACR_NAME  = "acrllmproyecto"
$CLUSTER   = "aks-llm-cluster"
$TENANT_ID = "ea671317-5e0d-4e35-8d02-6a7c57afb569"
$SUB_ID    = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"

# ─────────────────────────────────────────────────────────
# SESION AZURE
# ─────────────────────────────────────────────────────────
Write-Host "=== Verificando sesion Azure ===" -ForegroundColor Cyan
az account set --subscription $SUB_ID
$cuenta = az account show --output json | ConvertFrom-Json
Write-Host "Suscripcion activa: $($cuenta.name)" -ForegroundColor Green
Write-Host "ID: $($cuenta.id)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# FASE 2: Resource Group y ACR
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Creando Resource Group ===" -ForegroundColor Cyan
az group create --name $RG --location $LOCATION
Write-Host "Resource Group '$RG' listo." -ForegroundColor Green

Write-Host "=== Creando Azure Container Registry ===" -ForegroundColor Cyan
az acr create `
  --resource-group $RG `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled true
Write-Host "ACR '$ACR_NAME' listo." -ForegroundColor Green

Write-Host "=== Login Docker a ACR ===" -ForegroundColor Cyan
az acr login --name $ACR_NAME
Write-Host "Docker autenticado." -ForegroundColor Green

# ─────────────────────────────────────────────────────────
# FASE 3: Cluster AKS
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Creando cluster AKS (10-15 min) ===" -ForegroundColor Cyan
Write-Host "No cierres esta ventana..." -ForegroundColor Yellow

az aks create `
  --resource-group $RG `
  --name $CLUSTER `
  --location $LOCATION `
  --node-count 2 `
  --node-vm-size Standard_D4s_v3 `
  --enable-cluster-autoscaler `
  --min-count 1 `
  --max-count 3 `
  --attach-acr $ACR_NAME `
  --generate-ssh-keys `
  --network-plugin azure `
  --enable-managed-identity

Write-Host "Cluster CPU listo." -ForegroundColor Green

Write-Host "=== Agregando node pool GPU T4 spot ===" -ForegroundColor Cyan
az aks nodepool add `
  --resource-group $RG `
  --cluster-name $CLUSTER `
  --name gpunodes `
  --node-count 1 `
  --node-vm-size Standard_NC4as_T4_v3 `
  --enable-cluster-autoscaler `
  --min-count 0 `
  --max-count 4 `
  --node-taints sku=gpu:NoSchedule `
  --labels accelerator=nvidia-tesla-t4 `
  --priority Spot `
  --eviction-policy Delete `
  --spot-max-price -1

Write-Host "Node pool GPU listo." -ForegroundColor Green

Write-Host "=== Conectando kubectl al cluster ===" -ForegroundColor Cyan
az aks get-credentials `
  --resource-group $RG `
  --name $CLUSTER `
  --overwrite-existing

Write-Host ""
Write-Host "=== Verificando nodos ===" -ForegroundColor Cyan
kubectl get nodes -o wide

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  FASES 2 y 3 COMPLETADAS EXITOSAMENTE" -ForegroundColor Green
Write-Host "================================================"
Write-Host "  Resource Group : $RG"
Write-Host "  ACR            : $ACR_NAME.azurecr.io"
Write-Host "  Cluster AKS    : $CLUSTER"
Write-Host "  Nodos GPU      : Standard_NC4as_T4_v3 (spot)"
Write-Host "================================================"