# scripts\01_azure_setup.ps1
# ─────────────────────────────────────────────────────────
# CAMBIA ESTOS VALORES ANTES DE EJECUTAR
# ─────────────────────────────────────────────────────────
$RG         = "rg-llm-project"
$LOCATION   = "eastus"
$ACR_NAME   = "acrllmproyecto"   # CAMBIA ESTO: sin guiones, todo minúsculas, único globalmente
$CLUSTER    = "aks-llm-cluster"
# ─────────────────────────────────────────────────────────

Write-Host "=== Paso 1: Login a Azure ===" -ForegroundColor Cyan
az login

Write-Host "=== Paso 2: Ver suscripciones disponibles ===" -ForegroundColor Cyan
az account list --output table

Write-Host ""
Write-Host "Copia el ID de la suscripción que quieres usar y pégalo aquí:" -ForegroundColor Yellow
$SUB_ID = Read-Host "Subscription ID"
az account set --subscription $SUB_ID

Write-Host "=== Paso 3: Registrar providers (puede tardar 2-3 min) ===" -ForegroundColor Cyan
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
Write-Host "Providers registrados." -ForegroundColor Green

Write-Host "=== Paso 4: Crear Resource Group ===" -ForegroundColor Cyan
az group create --name $RG --location $LOCATION
Write-Host "Resource Group '$RG' creado en '$LOCATION'." -ForegroundColor Green

Write-Host "=== Paso 5: Crear Azure Container Registry ===" -ForegroundColor Cyan
az acr create `
  --resource-group $RG `
  --name $ACR_NAME `
  --sku Basic `
  --admin-enabled true
Write-Host "ACR '$ACR_NAME' creado." -ForegroundColor Green

Write-Host "=== Paso 6: Login al ACR con Docker ===" -ForegroundColor Cyan
az acr login --name $ACR_NAME
Write-Host "Docker autenticado con ACR." -ForegroundColor Green

Write-Host ""
Write-Host "=== FASE 2 COMPLETADA ===" -ForegroundColor Green
Write-Host "Resource Group : $RG"
Write-Host "ACR            : $ACR_NAME.azurecr.io"
Write-Host "Location       : $LOCATION"
Write-Host ""
Write-Host "Guarda estos valores, los usaremos en los siguientes scripts."

# Guardar variables en archivo para los siguientes pasos
@"
# Variables del proyecto - generado automáticamente
`$RG       = "$RG"
`$LOCATION = "$LOCATION"
`$ACR_NAME = "$ACR_NAME"
`$CLUSTER  = "$CLUSTER"
"@ | Out-File -FilePath "scripts\variables.ps1" -Encoding UTF8
Write-Host "Variables guardadas en scripts\variables.ps1" -ForegroundColor Cyan
