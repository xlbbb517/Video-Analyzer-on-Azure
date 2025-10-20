#!/usr/bin/env pwsh
# Video Analyzer On Azure Deployment Script
# Compatible with Windows PowerShell and PowerShell Core - Audio Analysis Support

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ParametersFile,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipValidation,
    
    [Parameter(Mandatory=$false)]
    [switch]$DeveloperMode,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Set encoding for Azure CLI to handle Unicode characters
$env:PYTHONIOENCODING = "utf-8"
$env:LC_ALL = "en_US.UTF-8"
$env:LANG = "en_US.UTF-8"

# Set console encoding for PowerShell
if ($PSVersionTable.PSVersion.Major -ge 6) {
    # PowerShell Core
    $OutputEncoding = [System.Text.Encoding]::UTF8
} else {
    # Windows PowerShell
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# Set strict mode
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color functions
function Write-Success { Write-Host $args[0] -ForegroundColor Green }
function Write-Warning { Write-Host $args[0] -ForegroundColor Yellow }
function Write-Error { Write-Host $args[0] -ForegroundColor Red }
function Write-Info { Write-Host $args[0] -ForegroundColor Cyan }

# Banner functions
function Show-StartBanner {
    Write-Host @"
 _   _ _     _                _                _                     
| | | (_) __| | ___  ___     / \   _ __   __ _| |_   _ _______ _ __ 
| | | | |/ _  |/ _ \/ _ \   / _ \ | '_ \ / _  | | | | |_  / _ \ '__|
| |_| | | (_| |  __/ (_) | / ___ \| | | | (_| | | |_| |/ /  __/ |   
 \___/|_|\__,_|\___|\___/ /_/   \_\_| |_|\__,_|_|\__, /___\___|_|   
                                                 |___/              
  ___           _                          
 / _ \ _ __    / \    _____   _ _ __ ___ 
| | | | '_ \  / _ \  |_  / | | | '__/ _ \
| |_| | | | |/ ___ \  / /| |_| | | |  __/
 \___/|_| |_/_/   \_\/___|\__,_|_|  \___|

Video Analyzer On Azure Deployment Starting...
"@ -ForegroundColor Cyan
}

function Show-SuccessBanner {
    Write-Host @"
 ____                              __       _ _ 
/ ___| _   _  ___ ___ ___ ___ ___  / _|_   _| | |
\___ \| | | |/ __/ __/ _ / __/ __|| |_| | | | | |
 ___) | |_| | (_| (_|  __\__ \__ \|  _| |_| | |_|
|____/ \__,_|\___\___\___|___|___/|_|  \__,_|_(_)
     _            _                                  _   _ 
  __| | ___ _ __ | | ___  _   _ _ __ ___   ___ _ __ | |_| |
 / _` | |/ _ \ '_ \| |/ _ \| | | | '_ ` _ \ / _ \ '_ \| __| |
| (_| |  __/ |_) | | (_) | |_| | | | | | |  __/ | | | |_|_|
 \__,_|\___| .__/|_|\___/ \__, |_| |_| |_|\___|_| |_|\__(_)
           |_|            |___/                            

"@ -ForegroundColor Green
}

function Show-ErrorBanner {
    Write-Host @"
 _____                     
|  ___| __ _ __ ___  _ __ 
| |__  | '__| '__/ _ \| '__|
|  __| | |  | | | (_) | |   
|_____||_|  |_|  \___/|_|  

An error occurred during deployment.
"@ -ForegroundColor Red
}

function Show-Help {
    Write-Host @"
Video Analyzer On Azure Deployment Script

USAGE:
    .\deploy.ps1 -ParametersFile <parameters-file> [OPTIONS]

OPTIONS:
    -ParametersFile         Required. Path to deploy.parameters.json file
    -SkipValidation         Optional. Skip resource validation for faster deployment
    -DeveloperMode          Optional. Grant deployer access to Azure resources
    -Help                   Show this help message

EXAMPLES:
    .\deploy.ps1 -ParametersFile deploy.parameters.json
    .\deploy.ps1 -ParametersFile deploy.parameters.json -DeveloperMode
    .\deploy.ps1 -ParametersFile deploy.parameters.json -SkipValidation

REQUIREMENTS:
    - PowerShell 5.1+ or PowerShell Core 7+
    - Azure CLI 2.55.0+
    - jq 1.6+ (Windows: choco install jq)
    - Docker (for building container images)

"@
}

# Global variables
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Global:Parameters = @{}

# Show help if requested
if ($Help) {
    Show-Help
    exit 0
}

function Test-Requirements {
    Write-Info "Checking requirements..."
    
    # Check jq
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Error "jq is required. Please install using: choco install jq"
        exit 1
    }
    
    $jqVersion = (jq --version) -replace 'jq-', ''
    if ([version]$jqVersion -lt [version]"1.6") {
        Write-Error "jq version 1.6 or higher is required. Current: $jqVersion"
        exit 1
    }
    
    # Check Azure CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is required. Please install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    }
    
    $azVersion = (az version --output json | ConvertFrom-Json).'azure-cli'
    if ([version]$azVersion -lt [version]"2.55.0") {
        Write-Error "Azure CLI version 2.55.0 or higher is required. Current: $azVersion"
        exit 1
    }
    
    # Check Docker
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warning "Docker not found. Container image building will be skipped."
    }
    
    Write-Success "Requirements check passed."
}

function Read-Parameters {
    Write-Info "Reading parameters from $ParametersFile..."
    
    if (-not (Test-Path $ParametersFile)) {
        Write-Error "Parameters file not found: $ParametersFile"
        exit 1
    }
    
    # Validate JSON
    try {
        $null = Get-Content $ParametersFile | jq empty
    } catch {
        Write-Error "Invalid JSON in parameters file"
        exit 1
    }
    
    # Read parameters into global variable
    $jsonContent = Get-Content $ParametersFile -Raw | ConvertFrom-Json
    
    # Required parameters
    $Global:LOCATION = $jsonContent.LOCATION
    $Global:RESOURCE_GROUP = $jsonContent.RESOURCE_GROUP
    
    if (-not $Global:LOCATION -or -not $Global:RESOURCE_GROUP) {
        Write-Error "Required parameters missing: LOCATION and RESOURCE_GROUP"
        exit 1
    }
    
    # Generate names if not provided
    $Global:RESOURCE_BASE_NAME = if ($jsonContent.RESOURCE_BASE_NAME) { $jsonContent.RESOURCE_BASE_NAME } else { "video-analyzer-$(Get-Random -Maximum 9999)" }
    $Global:CONTAINER_APP_ENV_NAME = if ($jsonContent.CONTAINER_APP_ENV_NAME) { $jsonContent.CONTAINER_APP_ENV_NAME } else { "${RESOURCE_BASE_NAME}-env" }
    $Global:CONTAINER_APP_NAME = if ($jsonContent.CONTAINER_APP_NAME) { $jsonContent.CONTAINER_APP_NAME } else { "${RESOURCE_BASE_NAME}-app" }
    $Global:ACR_NAME = if ($jsonContent.ACR_NAME) { $jsonContent.ACR_NAME } else { ($RESOURCE_BASE_NAME -replace '-', '').Substring(0, [Math]::Min(50, ($RESOURCE_BASE_NAME -replace '-', '').Length)) + (Get-Random -Maximum 999) }
    
    $Global:CHAT_OPENAI_SERVICE_NAME = if ($jsonContent.CHAT_OPENAI_SERVICE_NAME) { $jsonContent.CHAT_OPENAI_SERVICE_NAME } else { "${RESOURCE_BASE_NAME}-chat-openai" }
    $Global:AUDIO_OPENAI_SERVICE_NAME = if ($jsonContent.AUDIO_OPENAI_SERVICE_NAME) { $jsonContent.AUDIO_OPENAI_SERVICE_NAME } else { "${RESOURCE_BASE_NAME}-audio-openai" }
    
    # Chat model configuration
    $Global:AZURE_OPENAI_DEPLOYMENT_NAME = if ($jsonContent.AZURE_OPENAI_DEPLOYMENT_NAME) { $jsonContent.AZURE_OPENAI_DEPLOYMENT_NAME } else { "gpt-4.1-mini" }
    $Global:AZURE_OPENAI_API_VERSION = if ($jsonContent.AZURE_OPENAI_API_VERSION) { $jsonContent.AZURE_OPENAI_API_VERSION } else { "2024-02-15-preview" }
    $Global:CHAT_MODEL_NAME = if ($jsonContent.CHAT_MODEL_NAME) { $jsonContent.CHAT_MODEL_NAME } else { "gpt-4.1-mini" }
    $Global:CHAT_MODEL_VERSION = if ($jsonContent.CHAT_MODEL_VERSION) { $jsonContent.CHAT_MODEL_VERSION } else { "2025-04-14" }
    $Global:CHAT_SKU_CAPACITY = if ($jsonContent.CHAT_SKU_CAPACITY) { $jsonContent.CHAT_SKU_CAPACITY } else { "250" }
    $Global:CHAT_SKU_NAME = if ($jsonContent.CHAT_SKU_NAME) { $jsonContent.CHAT_SKU_NAME } else { "GlobalStandard" }
    $Global:CHAT_LOCATION = if ($jsonContent.AZURE_OPENAI_DEPLOYMENT_LOCATION) { $jsonContent.AZURE_OPENAI_DEPLOYMENT_LOCATION } else { $LOCATION }

    # Audio deployment names and API version
    $Global:AUDIO_DEPLOYMENT_NAME = if ($jsonContent.AUDIO_DEPLOYMENT_NAME) { $jsonContent.AUDIO_DEPLOYMENT_NAME } else { "gpt-4o-audio-preview" }
    $Global:AUDIO_DEPLOYMENT_NAME_V2 = if ($jsonContent.AUDIO_DEPLOYMENT_NAME_V2) { $jsonContent.AUDIO_DEPLOYMENT_NAME_V2 } else { "gpt-4o-transcribe" }
    $Global:AUDIO_DEPLOYMENT_NAME_V3 = if ($jsonContent.AUDIO_DEPLOYMENT_NAME_V3) { $jsonContent.AUDIO_DEPLOYMENT_NAME_V3 } else { "gpt-4o-mini-transcribe" }
    $Global:AUDIO_API_VERSION = if ($jsonContent.AUDIO_API_VERSION) { $jsonContent.AUDIO_API_VERSION } else { "2025-01-01-preview" }
    $Global:AUDIO_LOCATION = if ($jsonContent.AUDIO_DEPLOYMENT_LOCATION) { $jsonContent.AUDIO_DEPLOYMENT_LOCATION } else { $LOCATION }

    # Audio main model configuration
    $Global:AUDIO_MODEL_NAME = if ($jsonContent.AUDIO_MODEL_NAME) { $jsonContent.AUDIO_MODEL_NAME } else { "gpt-4o-audio-preview" }
    $Global:AUDIO_MODEL_VERSION = if ($jsonContent.AUDIO_MODEL_VERSION) { $jsonContent.AUDIO_MODEL_VERSION } else { "2024-12-17" }
    $Global:AUDIO_SKU_CAPACITY = if ($jsonContent.AUDIO_SKU_CAPACITY) { $jsonContent.AUDIO_SKU_CAPACITY } else { "250" }
    $Global:AUDIO_SKU_NAME = if ($jsonContent.AUDIO_SKU_NAME) { $jsonContent.AUDIO_SKU_NAME } else { "GlobalStandard" }
    
    # Audio V2 model configuration
    $Global:AUDIO_V2_MODEL_NAME = if ($jsonContent.AUDIO_V2_MODEL_NAME) { $jsonContent.AUDIO_V2_MODEL_NAME } else { "gpt-4o-transcribe" }
    $Global:AUDIO_V2_MODEL_VERSION = if ($jsonContent.AUDIO_V2_MODEL_VERSION) { $jsonContent.AUDIO_V2_MODEL_VERSION } else { "2025-03-20" }
    $Global:AUDIO_V2_SKU_CAPACITY = if ($jsonContent.AUDIO_V2_SKU_CAPACITY) { $jsonContent.AUDIO_V2_SKU_CAPACITY } else { "100" }
    $Global:AUDIO_V2_SKU_NAME = if ($jsonContent.AUDIO_V2_SKU_NAME) { $jsonContent.AUDIO_V2_SKU_NAME } else { "GlobalStandard" }
    
    # Audio V3 model configuration
    $Global:AUDIO_V3_MODEL_NAME = if ($jsonContent.AUDIO_V3_MODEL_NAME) { $jsonContent.AUDIO_V3_MODEL_NAME } else { "gpt-4o-mini-transcribe" }
    $Global:AUDIO_V3_MODEL_VERSION = if ($jsonContent.AUDIO_V3_MODEL_VERSION) { $jsonContent.AUDIO_V3_MODEL_VERSION } else { "2025-03-20" }
    $Global:AUDIO_V3_SKU_CAPACITY = if ($jsonContent.AUDIO_V3_SKU_CAPACITY) { $jsonContent.AUDIO_V3_SKU_CAPACITY } else { "100" }
    $Global:AUDIO_V3_SKU_NAME = if ($jsonContent.AUDIO_V3_SKU_NAME) { $jsonContent.AUDIO_V3_SKU_NAME } else { "GlobalStandard" }
    
    # Azure Storage configuration (optional)
    $Global:AZURE_STORAGE_ACCOUNT_NAME = $jsonContent.AZURE_STORAGE_ACCOUNT_NAME
    $Global:AZURE_STORAGE_ACCOUNT_KEY = $jsonContent.AZURE_STORAGE_ACCOUNT_KEY
    $Global:AZURE_STORAGE_CONTAINER_NAME = $jsonContent.AZURE_STORAGE_CONTAINER_NAME
    
    Write-Success "Parameters loaded successfully."
    Write-Info "Deployment Configuration:"
    Write-Host "  Resource Group: $RESOURCE_GROUP"
    Write-Host "  Location: $LOCATION"
    Write-Host "  Base Name: $RESOURCE_BASE_NAME"
    Write-Host "  Container Registry: $ACR_NAME"
    Write-Host "  Chat OpenAI Service: $CHAT_OPENAI_SERVICE_NAME, Location: $CHAT_LOCATION"
    Write-Host "  Audio OpenAI Service: $AUDIO_OPENAI_SERVICE_NAME, Location: $AUDIO_LOCATION"
    Write-Host "  Chat Model: $CHAT_MODEL_NAME v$CHAT_MODEL_VERSION (Capacity: $CHAT_SKU_CAPACITY, SKU: $CHAT_SKU_NAME)"
    Write-Host "  Audio Models:"
    Write-Host "    Main: $AUDIO_MODEL_NAME v$AUDIO_MODEL_VERSION (Capacity: $AUDIO_SKU_CAPACITY, SKU: $AUDIO_SKU_NAME)"
    Write-Host "    V2: $AUDIO_V2_MODEL_NAME v$AUDIO_V2_MODEL_VERSION (Capacity: $AUDIO_V2_SKU_CAPACITY, SKU: $AUDIO_V2_SKU_NAME)"
    Write-Host "    V3: $AUDIO_V3_MODEL_NAME v$AUDIO_V3_MODEL_VERSION (Capacity: $AUDIO_V3_SKU_CAPACITY, SKU: $AUDIO_V3_SKU_NAME)"
}

function Test-AzureLogin {
    Write-Info "Checking Azure login status..."
    
    try {
        $null = az account show 2>$null
    } catch {
        Write-Warning "Not logged in to Azure. Starting login process..."
        az login
        if (-not (az account show 2>$null)) {
            Write-Error "Failed to login to Azure"
            exit 1
        }
    }
    
    $accountInfo = az account show --output json | ConvertFrom-Json
    $userName = $accountInfo.user.name
    $subscriptionName = $accountInfo.name
    
    Write-Success "Logged in to Azure as: $userName"
    Write-Info "Subscription: $subscriptionName"
}

function Set-AzureCliDefaults {
    Write-Info "Setting Azure CLI defaults..."
    
    # Set default subscription if not in developer mode
    if (-not $DeveloperMode) {
        try {
            $subscriptionId = az account show --query id -o tsv
            az account set --subscription $subscriptionId --output none
            Write-Success "Default subscription set to: $subscriptionId"
        } catch {
            Write-Warning "Failed to set default subscription. Manual configuration may be required."
        }
    }
    
    # Set default resource group
    try {
        az configure --defaults group=$RESOURCE_GROUP --output none
        Write-Success "Default resource group set to: $RESOURCE_GROUP"
    } catch {
        Write-Warning "Failed to set default resource group. Manual configuration may be required."
    }
}

function New-ResourceGroup {
    Write-Info "Creating Azure Resource Group..."
    
    try {
        $null = az group show --name $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Resource group '$RESOURCE_GROUP' already exists."
    } else {
        Write-Info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        $createResult = az group create `
            --name $RESOURCE_GROUP `
            --location $LOCATION `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create resource group '$RESOURCE_GROUP'. See Azure CLI output above for details."
            throw "CreateResourceGroupFailed"
        }
        Write-Success "Resource group created successfully."
    }
}

function New-ChatOpenAIService {
    Write-Info "Creating Chat OpenAI Service..."
    
    # Check if service exists without throwing error
    try {
        $null = az cognitiveservices account show --name $CHAT_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME' already exists."
    } else {
        Write-Info "Creating Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME'..."
        $createResult = az cognitiveservices account create `
            --name $CHAT_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --location $CHAT_LOCATION `
            --kind OpenAI `
            --sku s0 `
            --custom-domain $CHAT_OPENAI_SERVICE_NAME `
            --yes `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME'. See Azure CLI output above for details."
            throw "CreateChatServiceFailed"
        }
        Write-Success "Chat OpenAI service created successfully."
    }
    
    # Deploy chat model
    Write-Info "Deploying chat model '$AZURE_OPENAI_DEPLOYMENT_NAME'..."
    try {
        $null = az cognitiveservices account deployment show `
            --name $CHAT_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AZURE_OPENAI_DEPLOYMENT_NAME `
            --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Chat model deployment already exists."
    } else {
        $createResult = az cognitiveservices account deployment create `
            --name $CHAT_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AZURE_OPENAI_DEPLOYMENT_NAME `
            --model-name $CHAT_MODEL_NAME `
            --model-version $CHAT_MODEL_VERSION `
            --model-format OpenAI `
            --sku-capacity $CHAT_SKU_CAPACITY `
            --sku-name $CHAT_SKU_NAME `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to deploy Chat model '$AZURE_OPENAI_DEPLOYMENT_NAME'. See Azure CLI output above for details."
            throw "DeployChatModelFailed"
        }
        Write-Success "Chat model deployed successfully."
    }
}

function New-AudioOpenAIService {
    Write-Info "Creating Audio OpenAI Service..."
    
    # Check if service exists without throwing error
    try {
        $null = az cognitiveservices account show --name $AUDIO_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME' already exists."
    } else {
        Write-Info "Creating Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME'..."
        $createResult = az cognitiveservices account create `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --location $AUDIO_LOCATION `
            --kind OpenAI `
            --sku s0 `
            --custom-domain $AUDIO_OPENAI_SERVICE_NAME `
            --yes `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME'. See Azure CLI output above for details."
            throw "CreateAudioServiceFailed"
        }
        Write-Success "Audio OpenAI service created successfully."
    }
    
    # Deploy main audio model
    Write-Info "Deploying main audio model '$AUDIO_DEPLOYMENT_NAME'..."
    try {
        $null = az cognitiveservices account deployment show `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME `
            --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if (-not $exists) {
        $createResult = az cognitiveservices account deployment create `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME `
            --model-name $AUDIO_MODEL_NAME `
            --model-version $AUDIO_MODEL_VERSION `
            --model-format OpenAI `
            --sku-capacity $AUDIO_SKU_CAPACITY `
            --sku-name $AUDIO_SKU_NAME `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to deploy Main audio model '$AUDIO_DEPLOYMENT_NAME'. See Azure CLI output above for details."
            throw "DeployAudioMainFailed"
        }
Write-Success "Main audio model deployed successfully."
    } else {
        Write-Success "Main audio model deployment already exists."
    }
    
    # Deploy Audio V2 model
    Write-Info "Deploying Audio V2 model '$AUDIO_DEPLOYMENT_NAME_V2'..."
    try {
        $null = az cognitiveservices account deployment show `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME_V2 `
            --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if (-not $exists) {
        $createResult = az cognitiveservices account deployment create `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME_V2 `
            --model-name $AUDIO_V2_MODEL_NAME `
            --model-version $AUDIO_V2_MODEL_VERSION `
            --model-format OpenAI `
            --sku-capacity $AUDIO_V2_SKU_CAPACITY `
            --sku-name $AUDIO_V2_SKU_NAME `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to deploy Audio V2 model '$AUDIO_DEPLOYMENT_NAME_V2'. See Azure CLI output above for details."
            throw "DeployAudioV2Failed"
        }
        Write-Success "Audio V2 model deployed successfully."
    } else {
        Write-Success "Audio V2 model deployment already exists."
    }
    
    # Deploy Audio V3 model
    Write-Info "Deploying Audio V3 model '$AUDIO_DEPLOYMENT_NAME_V3'..."
    try {
        $null = az cognitiveservices account deployment show `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME_V3 `
            --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if (-not $exists) {
        $createResult = az cognitiveservices account deployment create `
            --name $AUDIO_OPENAI_SERVICE_NAME `
            --resource-group $RESOURCE_GROUP `
            --deployment-name $AUDIO_DEPLOYMENT_NAME_V3 `
            --model-name $AUDIO_V3_MODEL_NAME `
            --model-version $AUDIO_V3_MODEL_VERSION `
            --model-format OpenAI `
            --sku-capacity $AUDIO_V3_SKU_CAPACITY `
            --sku-name $AUDIO_V3_SKU_NAME `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to deploy Audio V3 model '$AUDIO_DEPLOYMENT_NAME_V3'. See Azure CLI output above for details."
            throw "DeployAudioV3Failed"
        }
        Write-Success "Audio V3 model deployed successfully."
    } else {
        Write-Success "Audio V3 model deployment already exists."
    }
}

function New-ContainerRegistry {
    Write-Info "Creating Azure Container Registry..."
    
    try {
        $null = az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Container Registry '$ACR_NAME' already exists."
    } else {
        Write-Info "Creating Container Registry '$ACR_NAME'..."
        $createResult = az acr create `
            --resource-group $RESOURCE_GROUP `
            --name $ACR_NAME `
            --sku Basic `
            --admin-enabled true `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Container Registry '$ACR_NAME'. See Azure CLI output above for details."
            throw "CreateACRFailed"
        }
        Write-Success "Container Registry created successfully."
    }

    # Ensure we record the actual resource group where the ACR resides
    try {
        $actualAcrRg = az acr show --name $ACR_NAME --query resourceGroup -o tsv 2>$null
        if ($actualAcrRg) {
            $Global:ACR_RESOURCE_GROUP = $actualAcrRg
            Write-Info "Detected ACR resource group: $ACR_RESOURCE_GROUP"
        } else {
            # Fallback to the provided resource group
            $Global:ACR_RESOURCE_GROUP = $RESOURCE_GROUP
            Write-Warning "Could not detect ACR resource group, falling back to provided resource group: $ACR_RESOURCE_GROUP"
        }
    } catch {
        $Global:ACR_RESOURCE_GROUP = $RESOURCE_GROUP
        Write-Warning "Failed to query ACR info; using provided resource group: $ACR_RESOURCE_GROUP"
    }
}

function New-LogAnalyticsWorkspace {
    Write-Info "Creating Log Analytics Workspace..."
    
    $workspaceName = "${RESOURCE_BASE_NAME}-logs"
    
    try {
        $null = az monitor log-analytics workspace show --workspace-name $workspaceName --resource-group $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Log Analytics workspace already exists."
    } else {
        Write-Info "Creating Log Analytics workspace '$workspaceName'..."
        $createResult = az monitor log-analytics workspace create `
            --workspace-name $workspaceName `
            --resource-group $RESOURCE_GROUP `
            --location $LOCATION `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Log Analytics workspace '$workspaceName'. See Azure CLI output above for details."
            throw "CreateLogAnalyticsWorkspaceFailed"
        }
        Write-Success "Log Analytics workspace created successfully."
    }
    
    # Get workspace credentials
    $Global:LOG_ANALYTICS_WORKSPACE_ID = az monitor log-analytics workspace show `
        --workspace-name $workspaceName `
        --resource-group $RESOURCE_GROUP `
        --query customerId -o tsv
    
    $Global:LOG_ANALYTICS_WORKSPACE_KEY = az monitor log-analytics workspace get-shared-keys `
        --workspace-name $workspaceName `
        --resource-group $RESOURCE_GROUP `
        --query primarySharedKey -o tsv
}

function New-ContainerAppEnvironment {
    Write-Info "Creating Container App Environment..."
    
    try {
        $null = az containerapp env show --name $CONTAINER_APP_ENV_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
        $exists = $?
    } catch {
        $exists = $false
    }
    
    if ($exists) {
        Write-Success "Container App Environment already exists."
    } else {
        Write-Info "Creating Container App Environment '$CONTAINER_APP_ENV_NAME'..."
        $createResult = az containerapp env create `
            --name $CONTAINER_APP_ENV_NAME `
            --resource-group $RESOURCE_GROUP `
            --location $LOCATION `
            --logs-workspace-id $LOG_ANALYTICS_WORKSPACE_ID `
            --logs-workspace-key $LOG_ANALYTICS_WORKSPACE_KEY `
            --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create Container App Environment '$CONTAINER_APP_ENV_NAME'. See Azure CLI output above for details."
            throw "CreateContainerAppEnvFailed"
        }
        Write-Success "Container App Environment created successfully."
    }
}

function Update-EnvironmentFile {
    Write-Info "Updating .env file..."
    Write-Info "Retrieving OpenAI service endpoints and keys..."
    
    # Get API endpoints and keys
    $chatEndpoint = az cognitiveservices account show `
        --name $CHAT_OPENAI_SERVICE_NAME `
        --resource-group $RESOURCE_GROUP `
        --query properties.endpoint -o tsv
    
    $chatApiKey = az cognitiveservices account keys list `
        --name $CHAT_OPENAI_SERVICE_NAME `
        --resource-group $RESOURCE_GROUP `
        --query key1 -o tsv
    
    $audioEndpoint = az cognitiveservices account show `
        --name $AUDIO_OPENAI_SERVICE_NAME `
        --resource-group $RESOURCE_GROUP `
        --query properties.endpoint -o tsv
    
    $audioApiKey = az cognitiveservices account keys list `
        --name $AUDIO_OPENAI_SERVICE_NAME `
        --resource-group $RESOURCE_GROUP `
        --query key1 -o tsv
    
    $envFile = Join-Path $ScriptDir ".env"
    
    # Create .env file content
    $envContent = @"
# Video Analyzer On Azure Configuration
# Chat OpenAI Service
AZURE_OPENAI_ENDPOINT=$chatEndpoint
AZURE_OPENAI_API_KEY=$chatApiKey
AZURE_OPENAI_DEPLOYMENT_NAME=$AZURE_OPENAI_DEPLOYMENT_NAME
AZURE_OPENAI_API_VERSION=$AZURE_OPENAI_API_VERSION

# Audio OpenAI Service
AUDIO_ENDPOINT_URL=$audioEndpoint
AUDIO_AZURE_OPENAI_API_KEY=$audioApiKey
AUDIO_DEPLOYMENT_NAME=$AUDIO_DEPLOYMENT_NAME
AUDIO_DEPLOYMENT_NAME_V2=$AUDIO_DEPLOYMENT_NAME_V2
AUDIO_DEPLOYMENT_NAME_V3=$AUDIO_DEPLOYMENT_NAME_V3
AUDIO_API_VERSION=$AUDIO_API_VERSION
"@

    # Add storage configuration if present
    if ($AZURE_STORAGE_ACCOUNT_NAME) {
        $envContent += @"

# Azure Storage Configuration
AZURE_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME
AZURE_STORAGE_ACCOUNT_KEY=$AZURE_STORAGE_ACCOUNT_KEY
AZURE_STORAGE_CONTAINER_NAME=$AZURE_STORAGE_CONTAINER_NAME
"@
        Write-Success "Storage configuration added to .env file"
    }
    
    # Write to file
    $envContent | Out-File -FilePath $envFile -Encoding UTF8 -Force
    
    Write-Success ".env file updated successfully at: $envFile"
    
    Write-Info "Environment Configuration:"
    Write-Host "========================="
    Write-Host "  AZURE_OPENAI_ENDPOINT=$chatEndpoint"
    Write-Host "  AZURE_OPENAI_API_KEY=***CONFIGURED***"
    Write-Host "  AZURE_OPENAI_DEPLOYMENT_NAME=$AZURE_OPENAI_DEPLOYMENT_NAME"
    Write-Host "  AUDIO_ENDPOINT_URL=$audioEndpoint"
    Write-Host "  AUDIO_AZURE_OPENAI_API_KEY=***CONFIGURED***"
    Write-Host "  AUDIO_DEPLOYMENT_NAME=$AUDIO_DEPLOYMENT_NAME"
    Write-Host "  AUDIO_DEPLOYMENT_NAME_V2=$AUDIO_DEPLOYMENT_NAME_V2"
    Write-Host "  AUDIO_DEPLOYMENT_NAME_V3=$AUDIO_DEPLOYMENT_NAME_V3"
    
    if ($AZURE_STORAGE_ACCOUNT_NAME) {
        Write-Host "  AZURE_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME"
        Write-Host "  AZURE_STORAGE_ACCOUNT_KEY=***CONFIGURED***"
        Write-Host "  AZURE_STORAGE_CONTAINER_NAME=$AZURE_STORAGE_CONTAINER_NAME"
    }
    
    # Store for later use
    $Global:CHAT_ENDPOINT = $chatEndpoint
    $Global:CHAT_API_KEY = $chatApiKey
    $Global:AUDIO_ENDPOINT = $audioEndpoint
    $Global:AUDIO_API_KEY = $audioApiKey
}

function Build-ContainerImage {
    Write-Info "Building and pushing container image..."
    Write-Info "Target ACR: $ACR_NAME"
    Write-Info "Using Resource Group: $($Global:ACR_RESOURCE_GROUP ? $Global:ACR_RESOURCE_GROUP : $RESOURCE_GROUP)"

    # Determine which resource group to use for ACR operations
    $useAcrRg = if ($Global:ACR_RESOURCE_GROUP) { $Global:ACR_RESOURCE_GROUP } else { $RESOURCE_GROUP }

    # Verify ACR exists (try with discovered rg first)
    Write-Info "Verifying ACR access (resource group: $useAcrRg)..."
    $exists = az acr show --name $ACR_NAME --resource-group $useAcrRg --output none 2>$null
    if (-not $?) {
        Write-Warning "ACR '$ACR_NAME' not found in resource group '$useAcrRg'. Trying without specifying resource group..."
        $existsNoRg = az acr show --name $ACR_NAME --output none 2>$null
        if (-not $?) {
            Write-Error "Cannot access ACR '$ACR_NAME'. Please verify the registry name and resource group."
            exit 1
        } else {
            # update detected rg for future steps
            try {
                $detectedRg = az acr show --name $ACR_NAME --query resourceGroup -o tsv 2>$null
                if ($detectedRg) {
                    $Global:ACR_RESOURCE_GROUP = $detectedRg
                    Write-Info "Detected and using ACR resource group: $ACR_RESOURCE_GROUP"
                }
            } catch {
                Write-Warning "Could not determine ACR resource group after finding registry."
            }
        }
    }

    # Check if Dockerfile exists
    $dockerfilePath = Join-Path $ScriptDir "Dockerfile"
    if (-not (Test-Path $dockerfilePath)) {
        Write-Error "Dockerfile not found at: $dockerfilePath"
        exit 1
    }

    # Build and push image using ACR build
    Write-Info "Building and pushing image..."
    az acr build --registry $ACR_NAME --image video-analyzer:latest $ScriptDir

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Container image built and pushed successfully"
        # try to get login server
        try {
            $acrServer = az acr show --name $ACR_NAME --query loginServer -o tsv 2>$null
            if ($acrServer) {
                Write-Info "Image: $acrServer/video-analyzer:latest"
            } else {
                Write-Info "Image: $ACR_NAME.azurecr.io/video-analyzer:latest"
            }
        } catch {
            Write-Info "Image: $ACR_NAME.azurecr.io/video-analyzer:latest"
        }
    } else {
        Write-Error "Failed to build and push container image"
        exit 1
    }
}

function New-ContainerApp {
    Write-Info "Creating Container App..."
    Write-Info "Container App Name: $CONTAINER_APP_NAME"
    Write-Info "Environment: $CONTAINER_APP_ENV_NAME"
    Write-Info "Resource Group: $RESOURCE_GROUP"
    
    # Get ACR credentials
    Write-Info "Getting ACR credentials..."
    $acrServer = az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer -o tsv
    $acrUsername = az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query username -o tsv
    $acrPassword = az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query passwords[0].value -o tsv
    
    # Create Container App
    Write-Info "Deploying Container App with target port 5000..."
    $createResult = az containerapp create `
        --name $CONTAINER_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --environment $CONTAINER_APP_ENV_NAME `
        --image "$acrServer/video-analyzer:latest" `
        --target-port 5000 `
        --ingress 'external' `
        --min-replicas 0 `
        --max-replicas 2 `
        --cpu 1.0 `
        --memory 2.0Gi `
        --registry-server $acrServer `
        --registry-username $acrUsername `
        --registry-password $acrPassword `
        --env-vars "FLASK_ENV=production" `
        --output none
    
    if ($?) {
        # Get application URL
        $Global:APP_URL = az containerapp show `
            --name $CONTAINER_APP_NAME `
            --resource-group $RESOURCE_GROUP `
            --query properties.configuration.ingress.fqdn -o tsv
        
        Write-Success "Container App created successfully."
        Write-Success "App URL: https://$APP_URL"
    } else {
        Write-Error "Failed to create Container App"
        exit 1
    }
}

function Grant-DeveloperAccess {
    if (-not $DeveloperMode) {
        return
    }
    
    Write-Info "Granting developer access to Azure resources..."
    
    # Get current user
    $currentUser = az ad signed-in-user show --output json | ConvertFrom-Json
    $principalId = $currentUser.id
    
    # Grant Cognitive Services User role for both services
    $subscriptionId = (az account show --query id -o tsv)
    $chatResourceId = "/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$CHAT_OPENAI_SERVICE_NAME"
    $audioResourceId = "/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AUDIO_OPENAI_SERVICE_NAME"
    
    $null = az role assignment create `
        --role "Cognitive Services User" `
        --assignee $principalId `
        --scope $chatResourceId `
        --output none 2>$null
    
    $null = az role assignment create `
        --role "Cognitive Services User" `
        --assignee $principalId `
        --scope $audioResourceId `
        --output none 2>$null
    
    Write-Success "Developer access granted successfully."
}

function Test-Deployment {
    Write-Info "Verifying deployment..."
    
    $issues = @()
    
    # Check if services are accessible
    $exists = az cognitiveservices account show --name $CHAT_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
    if (-not $?) {
        $issues += "Chat OpenAI service not accessible"
    }
    
    $exists = az cognitiveservices account show --name $AUDIO_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output none 2>$null
    if (-not $?) {
        $issues += "Audio OpenAI service not accessible"
    }
    
    # Check model deployments
    $deployments = az cognitiveservices account deployment list --name $CHAT_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output json 2>$null | ConvertFrom-Json
    if ($deployments) {
        $chatDeployment = $deployments | Where-Object { $_.name -eq $AZURE_OPENAI_DEPLOYMENT_NAME }
        if ($chatDeployment -and $chatDeployment.properties.provisioningState -ne "Succeeded") {
            $issues += "Chat model deployment status: $($chatDeployment.properties.provisioningState)"
        }
    }
    
    $deployments = az cognitiveservices account deployment list --name $AUDIO_OPENAI_SERVICE_NAME --resource-group $RESOURCE_GROUP --output json 2>$null | ConvertFrom-Json
    if ($deployments) {
        $audioMainDeployment = $deployments | Where-Object { $_.name -eq $AUDIO_DEPLOYMENT_NAME }
        $audioV2Deployment = $deployments | Where-Object { $_.name -eq $AUDIO_DEPLOYMENT_NAME_V2 }
        $audioV3Deployment = $deployments | Where-Object { $_.name -eq $AUDIO_DEPLOYMENT_NAME_V3 }
        
        if ($audioMainDeployment -and $audioMainDeployment.properties.provisioningState -ne "Succeeded") {
            $issues += "Main audio model deployment status: $($audioMainDeployment.properties.provisioningState)"
        }
        if ($audioV2Deployment -and $audioV2Deployment.properties.provisioningState -ne "Succeeded") {
            $issues += "Audio V2 model deployment status: $($audioV2Deployment.properties.provisioningState)"
        }
        if ($audioV3Deployment -and $audioV3Deployment.properties.provisioningState -ne "Succeeded") {
            $issues += "Audio V3 model deployment status: $($audioV3Deployment.properties.provisioningState)"
        }
    }
    
    if ($issues.Count -eq 0) {
        Write-Success "All deployments verified successfully!"
    } else {
        Write-Warning "Configuration issues found:"
        foreach ($issue in $issues) {
            Write-Host "   - $issue"
        }
        Write-Host ""
        Write-Info "These issues may resolve automatically as Azure resources finish deploying."
    }
}

function Show-DeploymentSummary {
    Write-Info "Video Analyzer On Azure Deployment Summary:"
    Write-Host "==========================================="
    
    $containerAppUrl = az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv
    
    Write-Success "Application URL: https://$containerAppUrl"
    Write-Success "API Documentation: https://$containerAppUrl/docs"
    Write-Success "Chat OpenAI Service: $CHAT_OPENAI_SERVICE_NAME"
    Write-Success "Audio OpenAI Service: $AUDIO_OPENAI_SERVICE_NAME"
    Write-Success "Container Registry: $ACR_NAME"
    
    Write-Host ""
    Write-Success "Chat OpenAI Service - AUTOMATICALLY CONFIGURED"
    Write-Host "   - Endpoint: $CHAT_ENDPOINT"
    Write-Host "   - Deployment: $AZURE_OPENAI_DEPLOYMENT_NAME"
    Write-Host ""
    
    Write-Success "Audio OpenAI Service - AUTOMATICALLY CONFIGURED"
    Write-Host "   - Endpoint: $AUDIO_ENDPOINT"
    Write-Host "   - Main Model: $AUDIO_DEPLOYMENT_NAME"
    Write-Host "   - Audio V2: $AUDIO_DEPLOYMENT_NAME_V2"
    Write-Host "   - Audio V3: $AUDIO_DEPLOYMENT_NAME_V3"
    Write-Host ""
    
    Write-Success "Environment Variables - AUTOMATICALLY CONFIGURED"
    Write-Host "   - All keys and endpoints are automatically set in .env file"
    Write-Host "   - Container App environment variables are configured"
    Write-Host ""
    
    Test-Deployment
    
    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host "1. Wait 2-3 minutes for all services to fully start"
    Write-Host "2. Test your API at: https://$containerAppUrl/docs"
    Write-Host "3. Try the sample endpoints with your video files"
    Write-Host "4. Check logs if needed: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
    Write-Host ""
    
    Write-Info "Quick Test Command:"
    Write-Host @"
curl -X POST "https://$containerAppUrl/analyze-video-url" ``
     -H "Content-Type: application/json" ``
     -d '{
       "video_url": "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4",
       "user_prompt": "What is in this video?",
       "enable_audio_analysis": true,
       "audio_enable_v2": true,
       "audio_enable_v3": true,
       "max_frames": 6
     }'
"@
    Write-Host ""
    
    Write-Warning "Important Notes:"
    Write-Host "   1. API keys are automatically retrieved and configured"
    Write-Host "   2. No manual configuration required for basic functionality"
    Write-Host "   3. Check Azure OpenAI quota if you encounter rate limits"
    Write-Host "   4. Ensure your Azure subscription has sufficient credits"
}

# Main execution
function Main {
    try {
        Show-StartBanner
        
        Test-Requirements
        Read-Parameters
        Test-AzureLogin
        Set-AzureCliDefaults
        New-ResourceGroup
        New-ChatOpenAIService
        New-AudioOpenAIService
        Update-EnvironmentFile
        New-ContainerRegistry
        Build-ContainerImage
        New-LogAnalyticsWorkspace
        New-ContainerAppEnvironment
        New-ContainerApp
        Grant-DeveloperAccess
        
        Show-DeploymentSummary
        Show-SuccessBanner
        
        Write-Success "Video Analyzer On Azure deployment completed successfully!"
    }
    catch {
        Show-ErrorBanner
        Write-Error "Deployment failed: $_"
        Write-Error "Error at line: $($_.InvocationInfo.ScriptLineNumber)"
        exit 1
    }
}

# Run main function
Main