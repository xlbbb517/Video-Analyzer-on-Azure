# Azure Container Apps Deployment Script

# Set variables
$RESOURCE_GROUP = "video_analyzer_RG"
$LOCATION = "eastasia"
$CONTAINER_APP_ENV = "video-analyzer-solution"
$CONTAINER_APP_NAME = "video-analyzer-solution"
$ACR_NAME = "videoanalyzeracr" + (Get-Random -Maximum 9999)

Write-Host "Starting deployment of video analyzer app to Azure Container Apps..."

# 1. Check login status
Write-Host "Checking Azure login status..."
$loginCheck = az account show 2>$null
if (!$loginCheck) {
    Write-Host "Need to login to Azure"
    az login
}

# # 2. Create resource group
# Write-Host "Creating resource group: $RESOURCE_GROUP"
# az group create --name $RESOURCE_GROUP --location $LOCATION

# 3. Create Azure Container Registry
Write-Host "Creating container registry: $ACR_NAME"
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic

# 4. Enable admin user for ACR (needed for authentication)
Write-Host "Enabling admin user for ACR..."
az acr update --name $ACR_NAME --admin-enabled true --resource-group $RESOURCE_GROUP

# 5. Build and push image
Write-Host "Building and pushing image..."
az acr build --registry $ACR_NAME --image video-analyzer:latest . --resource-group $RESOURCE_GROUP

# 6. Get ACR credentials
Write-Host "Getting ACR credentials..."
$ACR_SERVER = az acr show --name $ACR_NAME --query loginServer -o tsv --resource-group $RESOURCE_GROUP
$ACR_USERNAME = az acr credential show --name $ACR_NAME --query username -o tsv --resource-group $RESOURCE_GROUP
$ACR_PASSWORD = az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv --resource-group $RESOURCE_GROUP

# 7. Create Container Apps environment
Write-Host "Creating Container Apps environment..."
az containerapp env create `
    --name $CONTAINER_APP_ENV `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION

# 8. Deploy Container App with registry credentials
Write-Host "Deploying application..."
az containerapp create `
    --name $CONTAINER_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $CONTAINER_APP_ENV `
    --image "$ACR_SERVER/video-analyzer:latest" `
    --target-port 5000 `
    --ingress external `
    --min-replicas 0 `
    --max-replicas 2 `
    --cpu 1.0 `
    --memory 2.0Gi `
    --registry-server $ACR_SERVER `
    --registry-username $ACR_USERNAME `
    --registry-password $ACR_PASSWORD `
    --env-vars "FLASK_ENV=production"

# 9. Get application URL
Write-Host "Deployment completed!"
$APP_URL = az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv
Write-Host "Application URL: https://$APP_URL"
Write-Host "Please save this URL to access your video analyzer application"