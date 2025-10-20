#!/usr/bin/env bash
# Video Analyzer On Azure Deployment Script
# Compatible with Linux and macOS - Audio Analysis Support

set -e  # Exit on any error

# Color functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_success() { printf "${GREEN}$1${NC}\n"; }
print_warning() { printf "${YELLOW}$1${NC}\n"; }
print_error() { printf "${RED}$1${NC}\n"; }
print_info() { printf "${CYAN}$1${NC}\n"; }

# Banner functions
show_start_banner() {
cat << "EOF"
 _   _ _     _                _                _                     
| | | (_) __| | ___  ___     / \   _ __   __ _| |_   _ _______ _ __ 
| | | | |/ _` |/ _ \/ _ \   / _ \ | '_ \ / _` | | | | |_  / _ \ '__|
| |_| | | (_| |  __/ (_) | / ___ \| | | | (_| | | |_| |/ /  __/ |   
 \___/|_|\__,_|\___|\___/ /_/   \_\_| |_|\__,_|_|\__, /___\___|_|   
                                                 |___/              
  ___           _                          
 / _ \ _ __    / \    _____   _ _ __ ___ 
| | | | '_ \  / _ \  |_  / | | | '__/ _ \
| |_| | | | |/ ___ \  / /| |_| | | |  __/
 \___/|_| |_/_/   \_\/___|\__,_|_|  \___|

Video Analyzer On Azure Deployment Starting...
EOF
}

show_success_banner() {
cat << "EOF"
 ____                              __       _ _ 
/ ___| _   _  ___ ___ ___ ___ ___  / _|_   _| | |
\___ \| | | |/ __/ __/ _ / __/ __|| |_| | | | | |
 ___) | |_| | (_| (_|  __\__ \__ \|  _| |_| | |_|
|____/ \__,_|\___\___\___|___|___/|_|  \__,_|_(_)
     _            _                                  _   _ 
  __| | ___ _ __ | | ___  _   _ _ __ ___   ___ _ __ | |_| |
 / _` |/ _ \ '_ \| |/ _ \| | | | '_ ` _ \ / _ \ '_ \| __| |
| (_| |  __/ |_) | | (_) | |_| | | | | | |  __/ | | | |_|_|
 \__,_|\___| .__/|_|\___/ \__, |_| |_| |_|\___|_| |_|\__(_)
           |_|            |___/                            

EOF
}

show_error_banner() {
cat << "EOF"
 _____                     
|  ___| __ _ __ ___  _ __ 
| |__  | '__| '__/ _ \| '__|
|  __| | |  | | | (_) | |   
|_____||_|  |_|  \___/|_|  

An error occurred during deployment.
EOF
}

show_help() {
cat << "EOF"
Video Analyzer On Azure Deployment Script

USAGE:
    ./deploy.sh [OPTIONS] -p <parameters-file>

OPTIONS:
    -p, --parameters-file   Required. Path to deploy.parameters.json file
    -s, --skip-validation   Optional. Skip resource validation for faster deployment
    -d, --developer-mode    Optional. Grant deployer access to Azure resources
    -h, --help              Show this help message

EXAMPLES:
    ./deploy.sh -p deploy.parameters.json
    ./deploy.sh -p deploy.parameters.json -d
    ./deploy.sh -p deploy.parameters.json -s

REQUIREMENTS:
    - Bash 4.0+
    - Azure CLI 2.55.0+
    - jq 1.6+
    - Docker (for building container images)

EOF
}

# Global variables
PARAMETERS_FILE=""
SKIP_VALIDATION=false
DEVELOPER_MODE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--parameters-file)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -s|--skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        -d|--developer-mode)
            DEVELOPER_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PARAMETERS_FILE" ]]; then
    print_error "Parameters file is required"
    show_help
    exit 1
fi

test_requirements() {
    print_info "Checking requirements..."
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq is required. Please install from https://stedolan.github.io/jq/"
        exit 1
    fi
    
    local jq_version
    jq_version=$(jq --version | cut -d'-' -f2)
    if [[ $(echo "$jq_version 1.6" | tr " " "\n" | sort -V | head -n1) != "1.6" ]]; then
        print_error "jq version 1.6 or higher is required. Current: $jq_version"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is required. Please install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    local az_version
    az_version=$(az version --output json | jq -r '.["azure-cli"]')
    if [[ $(echo "$az_version 2.55.0" | tr " " "\n" | sort -V | head -n1) != "2.55.0" ]]; then
        print_error "Azure CLI version 2.55.0 or higher is required. Current: $az_version"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not found. Container image building will be skipped."
    fi
    
    print_success "Requirements check passed."
}

read_parameters() {
    print_info "Reading parameters from $PARAMETERS_FILE..."
    
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi
    
    # Validate JSON
    if ! jq empty "$PARAMETERS_FILE" 2>/dev/null; then
        print_error "Invalid JSON in parameters file"
        exit 1
    fi
    
    # Read and validate required parameters
    LOCATION=$(jq -r '.LOCATION // empty' "$PARAMETERS_FILE")
    RESOURCE_GROUP=$(jq -r '.RESOURCE_GROUP // empty' "$PARAMETERS_FILE")
    
    if [[ -z "$LOCATION" || -z "$RESOURCE_GROUP" ]]; then
        print_error "Required parameters missing: LOCATION and RESOURCE_GROUP"
        exit 1
    fi
    
    # Generate names if not provided
    RESOURCE_BASE_NAME=$(jq -r '.RESOURCE_BASE_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$RESOURCE_BASE_NAME" ]]; then
        RESOURCE_BASE_NAME="video-analyzer-$(shuf -i 1000-9999 -n 1)"
    fi
    
    CONTAINER_APP_ENV_NAME=$(jq -r '.CONTAINER_APP_ENV_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$CONTAINER_APP_ENV_NAME" ]]; then
        CONTAINER_APP_ENV_NAME="${RESOURCE_BASE_NAME}-env"
    fi
    
    CONTAINER_APP_NAME=$(jq -r '.CONTAINER_APP_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$CONTAINER_APP_NAME" ]]; then
        CONTAINER_APP_NAME="${RESOURCE_BASE_NAME}-app"
    fi
    
    ACR_NAME=$(jq -r '.ACR_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$ACR_NAME" ]]; then
        ACR_NAME=$(echo "${RESOURCE_BASE_NAME}$(shuf -i 100-999 -n 1)" | tr -d '-' | cut -c1-50)
    fi
    
    CHAT_OPENAI_SERVICE_NAME=$(jq -r '.CHAT_OPENAI_SERVICE_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$CHAT_OPENAI_SERVICE_NAME" ]]; then
        CHAT_OPENAI_SERVICE_NAME="${RESOURCE_BASE_NAME}-chat-openai"
    fi
    
    AUDIO_OPENAI_SERVICE_NAME=$(jq -r '.AUDIO_OPENAI_SERVICE_NAME // empty' "$PARAMETERS_FILE")
    if [[ -z "$AUDIO_OPENAI_SERVICE_NAME" ]]; then
        AUDIO_OPENAI_SERVICE_NAME="${RESOURCE_BASE_NAME}-audio-openai"
    fi
    
    # Chat model configuration
    AZURE_OPENAI_DEPLOYMENT_NAME=$(jq -r '.AZURE_OPENAI_DEPLOYMENT_NAME // "gpt-4.1-mini"' "$PARAMETERS_FILE")
    AZURE_OPENAI_API_VERSION=$(jq -r '.AZURE_OPENAI_API_VERSION // "2024-02-15-preview"' "$PARAMETERS_FILE")
    CHAT_MODEL_NAME=$(jq -r '.CHAT_MODEL_NAME // "gpt-4.1-mini"' "$PARAMETERS_FILE")
    CHAT_MODEL_VERSION=$(jq -r '.CHAT_MODEL_VERSION // "2025-04-14"' "$PARAMETERS_FILE")
    CHAT_SKU_CAPACITY=$(jq -r '.CHAT_SKU_CAPACITY // "250"' "$PARAMETERS_FILE")
    CHAT_SKU_NAME=$(jq -r '.CHAT_SKU_NAME // "GlobalStandard"' "$PARAMETERS_FILE")
    CHAT_LOCATION=$(jq -r '.AZURE_OPENAI_DEPLOYMENT_LOCATION // .LOCATION' "$PARAMETERS_FILE")

    # Audio deployment names and API version
    AUDIO_DEPLOYMENT_NAME=$(jq -r '.AUDIO_DEPLOYMENT_NAME // "gpt-4o-audio-preview"' "$PARAMETERS_FILE")
    AUDIO_DEPLOYMENT_NAME_V2=$(jq -r '.AUDIO_DEPLOYMENT_NAME_V2 // "gpt-4o-transcribe"' "$PARAMETERS_FILE")
    AUDIO_DEPLOYMENT_NAME_V3=$(jq -r '.AUDIO_DEPLOYMENT_NAME_V3 // "gpt-4o-mini-transcribe"' "$PARAMETERS_FILE")
    AUDIO_API_VERSION=$(jq -r '.AUDIO_API_VERSION // "2025-01-01-preview"' "$PARAMETERS_FILE")
    AUDIO_LOCATION=$(jq -r '.AUDIO_DEPLOYMENT_LOCATION // .LOCATION' "$PARAMETERS_FILE")

    # Audio main model configuration
    AUDIO_MODEL_NAME=$(jq -r '.AUDIO_MODEL_NAME // "gpt-4o-audio-preview"' "$PARAMETERS_FILE")
    AUDIO_MODEL_VERSION=$(jq -r '.AUDIO_MODEL_VERSION // "2024-12-17"' "$PARAMETERS_FILE")
    AUDIO_SKU_CAPACITY=$(jq -r '.AUDIO_SKU_CAPACITY // "250"' "$PARAMETERS_FILE")
    AUDIO_SKU_NAME=$(jq -r '.AUDIO_SKU_NAME // "GlobalStandard"' "$PARAMETERS_FILE")
    
    # Audio V2 model configuration
    AUDIO_V2_MODEL_NAME=$(jq -r '.AUDIO_V2_MODEL_NAME // "gpt-4o-transcribe"' "$PARAMETERS_FILE")
    AUDIO_V2_MODEL_VERSION=$(jq -r '.AUDIO_V2_MODEL_VERSION // "2025-03-20"' "$PARAMETERS_FILE")
    AUDIO_V2_SKU_CAPACITY=$(jq -r '.AUDIO_V2_SKU_CAPACITY // "100"' "$PARAMETERS_FILE")
    AUDIO_V2_SKU_NAME=$(jq -r '.AUDIO_V2_SKU_NAME // "GlobalStandard"' "$PARAMETERS_FILE")
    
    # Audio V3 model configuration
    AUDIO_V3_MODEL_NAME=$(jq -r '.AUDIO_V3_MODEL_NAME // "gpt-4o-mini-transcribe"' "$PARAMETERS_FILE")
    AUDIO_V3_MODEL_VERSION=$(jq -r '.AUDIO_V3_MODEL_VERSION // "2025-03-20"' "$PARAMETERS_FILE")
    AUDIO_V3_SKU_CAPACITY=$(jq -r '.AUDIO_V3_SKU_CAPACITY // "100"' "$PARAMETERS_FILE")
    AUDIO_V3_SKU_NAME=$(jq -r '.AUDIO_V3_SKU_NAME // "GlobalStandard"' "$PARAMETERS_FILE")

    # Read Azure Storage configuration (optional)
    AZURE_STORAGE_ACCOUNT_NAME=$(jq -r '.AZURE_STORAGE_ACCOUNT_NAME // empty' "$PARAMETERS_FILE")
    AZURE_STORAGE_ACCOUNT_KEY=$(jq -r '.AZURE_STORAGE_ACCOUNT_KEY // empty' "$PARAMETERS_FILE")
    AZURE_STORAGE_CONTAINER_NAME=$(jq -r '.AZURE_STORAGE_CONTAINER_NAME // empty' "$PARAMETERS_FILE")

    print_success "Parameters loaded successfully."
    print_info "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Base Name: $RESOURCE_BASE_NAME"
    echo "  Container Registry: $ACR_NAME"
    echo "  Chat OpenAI Service: $CHAT_OPENAI_SERVICE_NAME, Location: $CHAT_LOCATION"
    echo "  Audio OpenAI Service: $AUDIO_OPENAI_SERVICE_NAME, Location: $AUDIO_LOCATION"
    echo "  Chat Model: $CHAT_MODEL_NAME v$CHAT_MODEL_VERSION (Capacity: $CHAT_SKU_CAPACITY, SKU: $CHAT_SKU_NAME)"
    echo "  Audio Models:"
    echo "    Main: $AUDIO_MODEL_NAME v$AUDIO_MODEL_VERSION (Capacity: $AUDIO_SKU_CAPACITY, SKU: $AUDIO_SKU_NAME)"
    echo "    V2: $AUDIO_V2_MODEL_NAME v$AUDIO_V2_MODEL_VERSION (Capacity: $AUDIO_V2_SKU_CAPACITY, SKU: $AUDIO_V2_SKU_NAME)"
    echo "    V3: $AUDIO_V3_MODEL_NAME v$AUDIO_V3_MODEL_VERSION (Capacity: $AUDIO_V3_SKU_CAPACITY, SKU: $AUDIO_V3_SKU_NAME)"
}

test_azure_login() {
    print_info "Checking Azure login status..."
    
    if ! az account show &>/dev/null; then
        print_warning "Not logged in to Azure. Starting login process..."
        az login
        if ! az account show &>/dev/null; then
            print_error "Failed to login to Azure"
            exit 1
        fi
    fi
    
    local account_info
    account_info=$(az account show --output json)
    local user_name
    local subscription_name
    user_name=$(echo "$account_info" | jq -r '.user.name')
    subscription_name=$(echo "$account_info" | jq -r '.name')
    
    print_success "Logged in to Azure as: $user_name"
    print_info "Subscription: $subscription_name"
}

create_resource_group() {
    print_info "Creating Azure Resource Group..."
    
    if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Resource group '$RESOURCE_GROUP' already exists."
    else
        print_info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create resource group '$RESOURCE_GROUP'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Resource group created successfully."
    fi
}

create_chat_openai_service() {
    print_info "Creating Chat OpenAI Service..."
    
    if az cognitiveservices account show --name "$CHAT_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME' already exists."
    else
        print_info "Creating Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME'..."
        az cognitiveservices account create \
            --name "$CHAT_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$CHAT_LOCATION" \
            --kind OpenAI \
            --sku s0 \
            --custom-domain "$CHAT_OPENAI_SERVICE_NAME" \
            --yes \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create Chat OpenAI service '$CHAT_OPENAI_SERVICE_NAME'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Chat OpenAI service created successfully."
    fi
    
    # Deploy chat model
    print_info "Deploying chat model '$AZURE_OPENAI_DEPLOYMENT_NAME'..."
    if az cognitiveservices account deployment show \
        --name "$CHAT_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$AZURE_OPENAI_DEPLOYMENT_NAME" \
        --output none 2>/dev/null; then
        print_success "Chat model deployment already exists."
    else
        az cognitiveservices account deployment create \
            --name "$CHAT_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$AZURE_OPENAI_DEPLOYMENT_NAME" \
            --model-name "$CHAT_MODEL_NAME" \
            --model-version "$CHAT_MODEL_VERSION" \
            --model-format OpenAI \
            --sku-capacity "$CHAT_SKU_CAPACITY" \
            --sku-name "$CHAT_SKU_NAME" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to deploy Chat model '$AZURE_OPENAI_DEPLOYMENT_NAME'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Chat model deployed successfully."
    fi
}

create_audio_openai_service() {
    print_info "Creating Audio OpenAI Service..."
    
    if az cognitiveservices account show --name "$AUDIO_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME' already exists."
    else
        print_info "Creating Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME'..."
        az cognitiveservices account create \
            --name "$AUDIO_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AUDIO_LOCATION" \
            --kind OpenAI \
            --sku s0 \
            --custom-domain "$AUDIO_OPENAI_SERVICE_NAME" \
            --yes \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create Audio OpenAI service '$AUDIO_OPENAI_SERVICE_NAME'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Audio OpenAI service created successfully."
    fi
    
    # Deploy main audio model
    print_info "Deploying main audio model '$AUDIO_DEPLOYMENT_NAME'..."
    if ! az cognitiveservices account deployment show \
        --name "$AUDIO_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$AUDIO_DEPLOYMENT_NAME" \
        --output none 2>/dev/null; then
        az cognitiveservices account deployment create \
            --name "$AUDIO_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$AUDIO_DEPLOYMENT_NAME" \
            --model-name "$AUDIO_MODEL_NAME" \
            --model-version "$AUDIO_MODEL_VERSION" \
            --model-format OpenAI \
            --sku-capacity "$AUDIO_SKU_CAPACITY" \
            --sku-name "$AUDIO_SKU_NAME" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to deploy Main audio model '$AUDIO_DEPLOYMENT_NAME'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Main audio model deployed successfully."
    else
        print_success "Main audio model deployment already exists."
    fi
    
    # Deploy Audio V2 model
    print_info "Deploying Audio V2 model '$AUDIO_DEPLOYMENT_NAME_V2'..."
    if ! az cognitiveservices account deployment show \
        --name "$AUDIO_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$AUDIO_DEPLOYMENT_NAME_V2" \
        --output none 2>/dev/null; then
        az cognitiveservices account deployment create \
            --name "$AUDIO_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$AUDIO_DEPLOYMENT_NAME_V2" \
            --model-name "$AUDIO_V2_MODEL_NAME" \
            --model-version "$AUDIO_V2_MODEL_VERSION" \
            --model-format OpenAI \
            --sku-capacity "$AUDIO_V2_SKU_CAPACITY" \
            --sku-name "$AUDIO_V2_SKU_NAME" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to deploy Audio V2 model '$AUDIO_DEPLOYMENT_NAME_V2'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Audio V2 model deployed successfully."
    else
        print_success "Audio V2 model deployment already exists."
    fi

    # Deploy Audio V3 model
    print_info "Deploying Audio V3 model '$AUDIO_DEPLOYMENT_NAME_V3'..."
    if ! az cognitiveservices account deployment show \
        --name "$AUDIO_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$AUDIO_DEPLOYMENT_NAME_V3" \
        --output none 2>/dev/null; then
        az cognitiveservices account deployment create \
            --name "$AUDIO_OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$AUDIO_DEPLOYMENT_NAME_V3" \
            --model-name "$AUDIO_V3_MODEL_NAME" \
            --model-version "$AUDIO_V3_MODEL_VERSION" \
            --model-format OpenAI \
            --sku-capacity "$AUDIO_V3_SKU_CAPACITY" \
            --sku-name "$AUDIO_V3_SKU_NAME" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to deploy Audio V3 model '$AUDIO_DEPLOYMENT_NAME_V3'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Audio V3 model deployed successfully."
    else
        print_success "Audio V3 model deployment already exists."
    fi
}

create_container_registry() {
    print_info "Creating Azure Container Registry..."
    
    if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Container Registry '$ACR_NAME' already exists."
    else
        print_info "Creating Container Registry '$ACR_NAME'..."
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ACR_NAME" \
            --sku Basic \
            --admin-enabled true \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create Container Registry '$ACR_NAME'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Container Registry created successfully."
    fi
}

create_log_analytics() {
    print_info "Creating Log Analytics Workspace..."
    
    local workspace_name="${RESOURCE_BASE_NAME}-logs"
    
    if az monitor log-analytics workspace show --workspace-name "$workspace_name" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Log Analytics workspace already exists."
    else
        print_info "Creating Log Analytics workspace '$workspace_name'..."
        az monitor log-analytics workspace create \
            --workspace-name "$workspace_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create Log Analytics workspace '$workspace_name'. See Azure CLI output above for details."
            exit 1
        fi
        print_success "Log Analytics workspace created successfully."
    fi
    
    # Get workspace credentials
    LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --workspace-name "$workspace_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId -o tsv)
    
    LOG_ANALYTICS_WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --workspace-name "$workspace_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query primarySharedKey -o tsv)
}

create_container_app_environment() {
    print_info "Creating Container App Environment..."
    
    if az containerapp env show --name "$CONTAINER_APP_ENV_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_success "Container App Environment already exists."
    else
        print_info "Creating Container App Environment '$CONTAINER_APP_ENV_NAME'..."
        az containerapp env create \
            --name "$CONTAINER_APP_ENV_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --logs-workspace-id "$LOG_ANALYTICS_WORKSPACE_ID" \
            --logs-workspace-key "$LOG_ANALYTICS_WORKSPACE_KEY" \
            --output none
        print_success "Container App Environment created successfully."
    fi
}

create_container_app() {
    print_info "Creating Container App..."
    
    # Get ACR credentials
    print_info "Getting ACR credentials..."
    local acr_server=$(az acr show --name "$ACR_NAME"  --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
    local acr_username=$(az acr credential show --name "$ACR_NAME"  --resource-group "$RESOURCE_GROUP" --query username -o tsv)
    local acr_password=$(az acr credential show --name "$ACR_NAME"  --resource-group "$RESOURCE_GROUP" --query passwords[0].value -o tsv)
    
    # Create Container App with registry credentials
    print_info "Deploying Container App with target port 5000..."
    if az containerapp create \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_APP_ENV_NAME" \
        --image "${acr_server}/video-analyzer:latest" \
        --target-port 5000 \
        --ingress 'external' \
        --min-replicas 0 \
        --max-replicas 2 \
        --cpu 1.0 \
        --memory 2.0Gi \
        --registry-server "$acr_server" \
        --registry-username "$acr_username" \
        --registry-password "$acr_password" \
        --env-vars "FLASK_ENV=production" \
        --output none; then
        
        # Get application URL
        APP_URL=$(az containerapp show \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query properties.configuration.ingress.fqdn -o tsv)
        
        print_success "Container App created successfully."
        print_success "App URL: https://$APP_URL"
    else
        print_error "Failed to create Container App"
        exit 1
    fi
}

build_container_image() {
    print_info "Building and pushing container image..."
    print_info "Target ACR: $ACR_NAME in Resource Group: $RESOURCE_GROUP"
    
    # Verify ACR exists
    print_info "Verifying ACR access..."
    if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        print_error "Cannot access ACR '$ACR_NAME' in resource group '$RESOURCE_GROUP'"
        exit 1
    fi
    
    # Check if Dockerfile exists
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        print_error "Dockerfile not found at: $SCRIPT_DIR/Dockerfile"
        exit 1
    fi
    
    print_info "Building and pushing image..."
    if az acr build --registry "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --image video-analyzer:latest "$SCRIPT_DIR"; then
        print_success "Container image built and pushed successfully"
        print_info "Image: $ACR_NAME.azurecr.io/video-analyzer:latest"
    else
        print_error "Failed to build and push container image"
        exit 1
    fi
}

update_environment_file() {
    print_info "Updating .env file..."
    print_info "Retrieving OpenAI service endpoints and keys..."
    
    # Get API endpoints and keys directly
    local chat_endpoint=$(az cognitiveservices account show \
        --name "$CHAT_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint -o tsv)
    
    local chat_api_key=$(az cognitiveservices account keys list \
        --name "$CHAT_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    
    local audio_endpoint=$(az cognitiveservices account show \
        --name "$AUDIO_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint -o tsv)
    
    local audio_api_key=$(az cognitiveservices account keys list \
        --name "$AUDIO_OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    
    local env_file="$SCRIPT_DIR/.env"
    
    cat > "$env_file" << EOF
# Video Analyzer On Azure Configuration
# Chat OpenAI Service
AZURE_OPENAI_ENDPOINT=$chat_endpoint
AZURE_OPENAI_API_KEY=$chat_api_key
AZURE_OPENAI_DEPLOYMENT_NAME=$AZURE_OPENAI_DEPLOYMENT_NAME
AZURE_OPENAI_API_VERSION=$AZURE_OPENAI_API_VERSION

# Audio OpenAI Service
AUDIO_ENDPOINT_URL=$audio_endpoint
AUDIO_AZURE_OPENAI_API_KEY=$audio_api_key
AUDIO_DEPLOYMENT_NAME=$AUDIO_DEPLOYMENT_NAME
AUDIO_DEPLOYMENT_NAME_V2=$AUDIO_DEPLOYMENT_NAME_V2
AUDIO_DEPLOYMENT_NAME_V3=$AUDIO_DEPLOYMENT_NAME_V3
AUDIO_API_VERSION=$AUDIO_API_VERSION
EOF

# Add storage configuration if present
    if [[ -n "$AZURE_STORAGE_ACCOUNT_NAME" ]]; then
        cat >> "$env_file" << EOF

# Azure Storage Configuration
AZURE_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME
AZURE_STORAGE_ACCOUNT_KEY=$AZURE_STORAGE_ACCOUNT_KEY
AZURE_STORAGE_CONTAINER_NAME=$AZURE_STORAGE_CONTAINER_NAME
EOF
    print_success "Storage configuration added to .env file"
fi

    print_success ".env file updated successfully at: $env_file"
    
    print_info "Environment Configuration:"
    echo "========================="
    echo "  AZURE_OPENAI_ENDPOINT=$chat_endpoint"
    echo "  AZURE_OPENAI_API_KEY=***CONFIGURED***"
    echo "  AZURE_OPENAI_DEPLOYMENT_NAME=$AZURE_OPENAI_DEPLOYMENT_NAME"
    echo "  AUDIO_ENDPOINT_URL=$audio_endpoint"
    echo "  AUDIO_AZURE_OPENAI_API_KEY=***CONFIGURED***"
    echo "  AUDIO_DEPLOYMENT_NAME=$AUDIO_DEPLOYMENT_NAME"
    echo "  AUDIO_DEPLOYMENT_NAME_V2=$AUDIO_DEPLOYMENT_NAME_V2"
    echo "  AUDIO_DEPLOYMENT_NAME_V3=$AUDIO_DEPLOYMENT_NAME_V3"

    if [[ -n "$AZURE_STORAGE_ACCOUNT_NAME" ]]; then
        echo "  AZURE_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME"
        echo "  AZURE_STORAGE_ACCOUNT_KEY=***CONFIGURED***"
        echo "  AZURE_STORAGE_CONTAINER_NAME=$AZURE_STORAGE_CONTAINER_NAME"
    fi
    
    # Store for later use in summary
    CHAT_ENDPOINT="$chat_endpoint"
    CHAT_API_KEY="$chat_api_key"
    AUDIO_ENDPOINT="$audio_endpoint"
    AUDIO_API_KEY="$audio_api_key"
}

grant_developer_access() {
    if [[ "$DEVELOPER_MODE" != "true" ]]; then
        return 0
    fi
    
    print_info "Granting developer access to Azure resources..."
    
    # Get current user
    local current_user
    local principal_id
    
    current_user=$(az ad signed-in-user show --output json)
    principal_id=$(echo "$current_user" | jq -r '.id')
    
    # Grant Cognitive Services User role for both services
    local chat_resource_id="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$CHAT_OPENAI_SERVICE_NAME"
    local audio_resource_id="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AUDIO_OPENAI_SERVICE_NAME"
    
    az role assignment create \
        --role "Cognitive Services User" \
        --assignee "$principal_id" \
        --scope "$chat_resource_id" \
        --output none || true
    
    az role assignment create \
        --role "Cognitive Services User" \
        --assignee "$principal_id" \
        --scope "$audio_resource_id" \
        --output none || true
    
    print_success "Developer access granted successfully."
}

verify_deployment() {
    print_info "Verifying deployment..."
    
    local issues=()
    
    # Check if services are accessible
    if ! az cognitiveservices account show --name "$CHAT_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        issues+=("Chat OpenAI service not accessible")
    fi
    
    if ! az cognitiveservices account show --name "$AUDIO_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
        issues+=("Audio OpenAI service not accessible")
    fi
    
    # Check model deployments
    local deployments
    if deployments=$(az cognitiveservices account deployment list --name "$CHAT_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null); then
        local chat_deployment_status
        chat_deployment_status=$(echo "$deployments" | jq -r ".[] | select(.name == \"$AZURE_OPENAI_DEPLOYMENT_NAME\") | .properties.provisioningState")
        
        if [[ "$chat_deployment_status" != "Succeeded" ]]; then
            issues+=("Chat model deployment status: $chat_deployment_status")
        fi
    fi
    
    if deployments=$(az cognitiveservices account deployment list --name "$AUDIO_OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --output json 2>/dev/null); then
        local audio_main_status audio_v2_status audio_v3_status
        audio_main_status=$(echo "$deployments" | jq -r ".[] | select(.name == \"$AUDIO_DEPLOYMENT_NAME\") | .properties.provisioningState")
        audio_v2_status=$(echo "$deployments" | jq -r ".[] | select(.name == \"$AUDIO_DEPLOYMENT_NAME_V2\") | .properties.provisioningState")
        audio_v3_status=$(echo "$deployments" | jq -r ".[] | select(.name == \"$AUDIO_DEPLOYMENT_NAME_V3\") | .properties.provisioningState")
        
        if [[ "$audio_main_status" != "Succeeded" ]]; then
            issues+=("Main audio model deployment status: $audio_main_status")
        fi
        if [[ "$audio_v2_status" != "Succeeded" ]]; then
            issues+=("Audio V2 model deployment status: $audio_v2_status")
        fi
        if [[ "$audio_v3_status" != "Succeeded" ]]; then
            issues+=("Audio V3 model deployment status: $audio_v3_status")
        fi
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        print_success "All deployments verified successfully!"
    else
        print_warning "Configuration issues found:"
        for issue in "${issues[@]}"; do
            echo "   - $issue"
        done
        echo ""
        print_info "These issues may resolve automatically as Azure resources finish deploying."
    fi
}

show_deployment_summary() {
    print_info "Video Analyzer On Azure Deployment Summary:"
    echo "==========================================="
    
    local container_app_url
    container_app_url=$(az containerapp show --name "$CONTAINER_APP_NAME" --resource-group "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv)
    
    print_success "Application URL: https://$container_app_url"
    print_success "API Documentation: https://$container_app_url/docs"
    print_success "Chat OpenAI Service: $CHAT_OPENAI_SERVICE_NAME"
    print_success "Audio OpenAI Service: $AUDIO_OPENAI_SERVICE_NAME"
    print_success "Container Registry: $ACR_NAME"
    
    echo ""
    print_success "Chat OpenAI Service - AUTOMATICALLY CONFIGURED"
    echo "   - Endpoint: $CHAT_ENDPOINT"
    echo "   - Deployment: $AZURE_OPENAI_DEPLOYMENT_NAME"
    echo ""
    
    print_success "Audio OpenAI Service - AUTOMATICALLY CONFIGURED"
    echo "   - Endpoint: $AUDIO_ENDPOINT"
    echo "   - Main Model: $AUDIO_DEPLOYMENT_NAME"
    echo "   - Audio V2: $AUDIO_DEPLOYMENT_NAME_V2"
    echo "   - Audio V3: $AUDIO_DEPLOYMENT_NAME_V3"
    echo ""
    
    print_success "Environment Variables - AUTOMATICALLY CONFIGURED"
    echo "   - All keys and endpoints are automatically set in .env file"
    echo "   - Container App environment variables are configured"
    echo ""
    
    verify_deployment
    
    echo ""
    print_info "Next Steps:"
    echo "1. Wait 2-3 minutes for all services to fully start"
    echo "2. Test your API at: https://$container_app_url/docs"
    echo "3. Try the sample endpoints with your video files"
    echo "4. Check logs if needed: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
    echo ""
    
    print_info "Quick Test Command:"
    cat << EOF
curl -X POST "https://$container_app_url/analyze-video-url" \\
     -H "Content-Type: application/json" \\
     -d '{
       "video_url": "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4",
       "user_prompt": "What is in this video?",
       "enable_audio_analysis": true,
       "audio_enable_v2": true,
       "audio_enable_v3": true,
       "max_frames": 6
     }'
EOF
    echo ""
    
    print_warning "Important Notes:"
    echo "   1. API keys are automatically retrieved and configured"
    echo "   2. No manual configuration required for basic functionality"
    echo "   3. Check Azure OpenAI quota if you encounter rate limits"
    echo "   4. Ensure your Azure subscription has sufficient credits"
}

# Main execution
main() {
    # Error handling
    trap 'show_error_banner; print_error "Deployment failed at line $LINENO"; exit 1' ERR
    
    show_start_banner
    
    test_requirements
    read_parameters
    test_azure_login
    create_resource_group
    create_chat_openai_service
    create_audio_openai_service
    update_environment_file
    create_container_registry
    build_container_image
    create_log_analytics
    create_container_app_environment
    create_container_app
    grant_developer_access
    
    show_deployment_summary
    show_success_banner
    
    print_success "Video Analyzer On Azure deployment completed successfully!"
}

# Run main function
main "$@"