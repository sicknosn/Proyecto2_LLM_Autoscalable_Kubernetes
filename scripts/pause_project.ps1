# scripts\pause_project.ps1

$RG      = "rg-llm-project"
$CLUSTER = "aks-llm-cluster"
$SUB_ID  = "a3fc48ab-4e2c-46fb-9b14-0d83d63e470a"

az account set --subscription $SUB_ID

Write-Host "=== Deteniendo cluster AKS ===" -ForegroundColor Yellow

# Escalar nodepool CPU a 0 (no se puede apagar system pool, lo dejamos en 1 minimo)
az aks nodepool scale `
  --resource-group $RG `
  --cluster-name $CLUSTER `
  --name nodepool1 `
  --node-count 1

# Detener el cluster completo (pausa VMs, no borra nada)
az aks stop `
  --resource-group $RG `
  --name $CLUSTER

Write-Host "================================================" -ForegroundColor Green
Write-Host "  Cluster detenido. No se cobra por VMs." -ForegroundColor Green
Write-Host "  ACR sigue corriendo (~$0.005/hr, casi nada)." -ForegroundColor Green
Write-Host "================================================"