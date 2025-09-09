#!/bin/bash

############### USAGE ################
# ./deploy.sh [options]
# Options:
#   --type <type>                Execution type: plan or deploy (required)
#   --tenant-id <id>             Azure Tenant ID
#   --client-id <id>             Azure Client ID
#   --subscription-id <id>       Azure Subscription ID
#   --client-secret <secret>     Azure Client Secret
#   --template-file <file>       Bicep template file (default: main.bicep)
#   --parameters-file <file>     Parameters file for Bicep template (supports .bicepparam or .json formats)
#   --param <key=value>          Bicep template parameter (can be used multiple times)
#   --location <location>        Azure region (default: eastus)
#   --resource-group-name <name> Resource group name (default: rg-bicep-deployment)
#   --deployment-name <name>     Deployment name (default: bicep-deployment)
#   --deployment-mode            Deployment mode: incremental or complete (default: incremental)
#   --delete-rg                  Delete resource group and exit (deploy mode only)
#   --create-rg                  Create resource group if it doesn't exist (plan mode only)
#   --debug                      Enable debug mode
#   --help                       Display this help message
#
# Examples:
#   ./deploy.sh --type plan --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type deploy --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type plan --create-rg --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type deploy --delete-rg --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type deploy --template-file custom.bicep --location westus2 --resource-group-name rg-custom --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type deploy --param keyVaultName=my-kv --param skuName=premium --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type plan --parameters-file params.bicepparam --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type plan --parameters-file params.json --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
#   ./deploy.sh --type deploy --parameters-file params.bicepparam --param keyVaultName=my-kv --param skuName=premium --tenant-id "xxx" --client-id "xxx" --subscription-id "xxx" --client-secret "xxx"
######################################

######### VARIABLE HIERARCHY #########
# 1. Command line arguments (highest priority)
# 2. Environment variables (fallback)
# 3. Default values (lowest priority, where applicable)
#
# Required variables (no defaults):
# - TYPE (plan or deploy)
# - TENANT_ID
# - CLIENT_ID
# - SUBSCRIPTION_ID
# - CLIENT_SECRET
######################################

# Initialize global variables
BICEP_PARAMS=()

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --type <type>                Execution type: plan or deploy (required)"
    echo "  --tenant-id <id>             Azure Tenant ID"
    echo "  --client-id <id>             Azure Client ID"
    echo "  --subscription-id <id>       Azure Subscription ID"
    echo "  --client-secret <secret>     Azure Client Secret"
    echo "  --template-file <file>       Bicep template file (default: main.bicep)"
    echo "  --parameters-file <file>     Parameters file for Bicep template (supports .bicepparam or .json formats)"
    echo "  --param <key=value>          Bicep template parameter (can be used multiple times)"
    echo "  --location <location>        Azure region (default: eastus)"
    echo "  --resource-group-name <name> Resource group name (default: rg-bicep-deployment)"
    echo "  --deployment-name <name>     Deployment name (default: bicep-deployment)"
    echo "  --deployment-mode            Deployment mode: incremental or complete (default: incremental)"
    echo "  --delete-rg                  Delete resource group and exit (deploy mode only)"
    echo "  --create-rg                  Create resource group if it doesn't exist (plan mode only)"
    echo "  --debug                      Enable debug mode"
    echo "  --help                       Display this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic usage (requires Azure credentials)"
    echo "  $0 --type plan --tenant-id \"xxx\" --client-id \"xxx\" --subscription-id \"xxx\" --client-secret \"xxx\""
    echo ""
    echo "  # Deploy with custom template and parameters"
    echo "  $0 --type deploy --template-file custom.bicep --param keyVaultName=my-kv"
    echo ""
    echo "  # Use parameters file"
    echo "  $0 --type plan --parameters-file params.bicepparam"
    echo ""
    echo "  # Resource group management"
    echo "  $0 --type plan --create-rg"
    echo "  $0 --type deploy --delete-rg"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --type)
            ARG_TYPE="$2"
            shift 2
            ;;
        --tenant-id)
            ARG_TENANT_ID="$2"
            shift 2
            ;;
        --client-id)
            ARG_CLIENT_ID="$2"
            shift 2
            ;;
        --subscription-id)
            ARG_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --client-secret)
            ARG_CLIENT_SECRET="$2"
            shift 2
            ;;
        --template-file)
            ARG_TEMPLATE_FILE="$2"
            shift 2
            ;;
        --parameters-file)
            ARG_PARAMETERS_FILE="$2"
            shift 2
            ;;
        --param)
            BICEP_PARAMS+=("$2")
            shift 2
            ;;
        --location)
            ARG_LOCATION="$2"
            shift 2
            ;;
        --resource-group-name)
            ARG_RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --deployment-name)
            ARG_DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        --deployment-mode)
            ARG_DEPLOYMENT_MODE="$2"
            shift 2
            ;;
        --delete-rg)
            DELETE_RG_FLAG=true
            shift
            ;;
        --create-rg)
            CREATE_RG_FLAG=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        --debug)
            DEBUG_FLAG=true
            shift
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            exit 1
            ;;
        esac
    done
}

# Function to set variables with hierarchy
set_variables() {
    # Required variables
    TYPE="${ARG_TYPE:-${TYPE}}"
    TENANT_ID="${ARG_TENANT_ID:-${AZURE_TENANT_ID}}"
    CLIENT_ID="${ARG_CLIENT_ID:-${AZURE_CLIENT_ID}}"
    SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}"
    CLIENT_SECRET="${ARG_CLIENT_SECRET:-${AZURE_CLIENT_SECRET}}"

    # Optional variables
    TEMPLATE_FILE="${ARG_TEMPLATE_FILE:-${TEMPLATE_FILE}}"
    PARAMETERS_FILE="${ARG_PARAMETERS_FILE:-${PARAMETERS_FILE}}"
    LOCATION="${ARG_LOCATION:-${LOCATION:-"eastus"}}"
    RESOURCE_GROUP_NAME="${ARG_RESOURCE_GROUP_NAME:-${RESOURCE_GROUP_NAME:-"rg-bicep-deployment"}}"
    DEPLOYMENT_NAME="${ARG_DEPLOYMENT_NAME:-${DEPLOYMENT_NAME:-"bicep-deployment"}}"
    DEPLOYMENT_MODE="${ARG_DEPLOYMENT_MODE:-${DEPLOYMENT_MODE:-"incremental"}}"
}

# Function to validate inputs
validate_inputs() {
    if [ -z "${TYPE}" ]; then
        echo "[ERROR] TYPE is required (provide via --type: plan or deploy)"
        exit 1
    fi

    if [[ "${TYPE}" != "plan" && "${TYPE}" != "deploy" ]]; then
        echo "[ERROR] TYPE must be either 'plan' or 'deploy'"
        exit 1
    fi

    if [[ "${TYPE}" == "plan" && "${DELETE_RG_FLAG}" == true ]]; then
        echo "[ERROR] --delete-rg flag is only valid with the deploy type"
        exit 1
    fi

    if [[ "${TYPE}" == "deploy" && "${CREATE_RG_FLAG}" == true ]]; then
        echo "[ERROR] --create-rg flag is only valid with the deploy type"
        exit 1
    fi

    if [ -z "${TENANT_ID}" ]; then
        echo "[ERROR] TENANT_ID is required (provide via --tenant-id or environment variable)"
        exit 1
    fi

    if [ -z "${CLIENT_ID}" ]; then
        echo "[ERROR] CLIENT_ID is required (provide via --client-id or environment variable)"
        exit 1
    fi

    if [ -z "${SUBSCRIPTION_ID}" ]; then
        echo "[ERROR] SUBSCRIPTION_ID is required (provide via --subscription-id or environment variable)"
        exit 1
    fi

    if [ -z "${CLIENT_SECRET}" ]; then
        echo "[ERROR] CLIENT_SECRET is required (provide via --client-secret or environment variable)"
        exit 1
    fi

    # Validate bicepparam file usage
    if [[ ! -z "${PARAMETERS_FILE}" ]]; then
        if [[ ! -f "${PARAMETERS_FILE}" ]]; then
            echo "[ERROR] Parameters file '${PARAMETERS_FILE}' not found"
            exit 1
        fi
        
        if [[ "${PARAMETERS_FILE}" == *.bicepparam ]]; then
            if [[ ${#BICEP_PARAMS[@]} -gt 0 ]]; then
                echo "[ERROR] Cannot combine .bicepparam file with individual --param arguments"
                echo "[ERROR] When using a .bicepparam file, all parameters must be defined within the file"
                exit 1
            fi

            if [[ ! -z "${TEMPLATE_FILE}" ]]; then
                echo "[ERROR] Cannot specify template file when using a .bicepparam file"
                echo "[ERROR] The .bicepparam file already references the template with the 'using' directive"
                exit 1
            fi
        elif [[ "${PARAMETERS_FILE}" != *.json ]]; then
            echo "[ERROR] Invalid parameters file"
            echo "[ERROR] File '${PARAMETERS_FILE}' must have either .bicepparam or .json extension"
            exit 1
        fi
    fi
}

# Function to display configuration
display_configuration() {
    echo ""
    echo "Configuration"
    echo "---------------------------------------"
    echo ""
    echo "[INFO] TYPE: ${TYPE}"

    if [ ! -z "${TEMPLATE_FILE}" ]; then
        echo ""
        echo "[INFO] TEMPLATE_FILE: ${TEMPLATE_FILE}"
    fi
    if [ ! -z "${PARAMETERS_FILE}" ]; then
        echo ""
        echo "[INFO] PARAMETERS_FILE: ${PARAMETERS_FILE}"
    fi
    if [ ${#BICEP_PARAMS[@]} -gt 0 ]; then
        echo ""
        echo "[INFO] BICEP_PARAMS: ${BICEP_PARAMS[*]}"
    fi
    echo ""

    echo "[INFO] TENANT_ID: ${TENANT_ID}"
    echo "[INFO] CLIENT_ID: ${CLIENT_ID}"
    echo "[INFO] SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
    echo ""
    echo "[INFO] LOCATION: ${LOCATION}"
    echo "[INFO] RESOURCE_GROUP_NAME: ${RESOURCE_GROUP_NAME}"
    echo ""
    echo "[INFO] DEPLOYMENT_NAME: ${DEPLOYMENT_NAME}"
    echo "[INFO] DEPLOYMENT_MODE: ${DEPLOYMENT_MODE}"
    echo ""
}

# Function to build parameter arguments for Azure CLI
build_param_args() {
    local param_args=""

    # Add parameters file if specified
    if [ ! -z "${PARAMETERS_FILE}" ]; then
        param_args+=" --parameters ${PARAMETERS_FILE}"
    fi

    if [ ${#BICEP_PARAMS[@]} -gt 0 ]; then
        # Add individual parameters
        for param in "${BICEP_PARAMS[@]}"; do
            param_args+=" --parameters ${param}"
        done
    fi

    echo "${param_args}"
}

# Function to handle resource group operations
handle_resource_group() {
    echo ""
    echo "---------------------------------------"
    echo "|    Resource Group Configuration     |"
    echo "---------------------------------------"
    echo ""

    if az group show --name "${RESOURCE_GROUP_NAME}" ${DEBUG_FLAG:+--debug} 2>/dev/null; then
        if [[ "${TYPE}" == "deploy" ]]; then
            if [[ "${DELETE_RG_FLAG}" == true ]]; then
                echo ""
                echo "Deleting Resource Group"
                echo "---------------------------------------"
                echo ""

                az group delete \
                    --name "${RESOURCE_GROUP_NAME}" \
                    --yes \
                    ${DEBUG_FLAG:+--debug}

                echo "[INFO] Resource Group Deleted."
                echo ""
                exit 0
            fi
        fi
    else
        if [[ "${TYPE}" == "plan" && "${CREATE_RG_FLAG}" != true ]]; then
            echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' does not exist."
            echo "[INFO] Use --create-rg flag to create it automatically."
            exit 0
        fi

        echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' does not exist."
        echo ""
        echo "Creating Resource Group"
        echo "---------------------------------------"
        echo ""
        az group create \
            --name "${RESOURCE_GROUP_NAME}" \
            --location "${LOCATION}" \
            ${DEBUG_FLAG:+--debug}

        echo ""
        echo "[INFO] Resource group created."
    fi

    echo ""
}

# Function to execute deployment plan (what-if)
execute_deployment_plan() {
    echo "---------------------------------------"
    echo "|       Main Deployment What-If       |"
    echo "---------------------------------------"
    echo ""

    PARAM_ARGS=$(build_param_args)

    az deployment group what-if \
        --name "${DEPLOYMENT_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --mode "${DEPLOYMENT_MODE}" \
        ${TEMPLATE_FILE:+--template-file "${TEMPLATE_FILE}"} \
        ${PARAM_ARGS} \
        ${DEBUG_FLAG:+--debug}

    echo ""
    echo "---------------------------------------"
    echo "|     Deployment What-If Complete     |"
    echo "---------------------------------------"
    echo ""

}

# Function to execute deployment
execute_deployment() {
    echo "---------------------------------------"
    echo "|         Main Deployment             |"
    echo "---------------------------------------"
    echo ""

    PARAM_ARGS=$(build_param_args)

    az deployment group create \
        --name "${DEPLOYMENT_NAME}" \
        --resource-group "${RESOURCE_GROUP_NAME}" \
        --mode "${DEPLOYMENT_MODE}" \
        ${TEMPLATE_FILE:+--template-file "${TEMPLATE_FILE}"} \
        ${PARAM_ARGS} \
        ${DEBUG_FLAG:+--debug}

    echo ""
    echo "---------------------------------------"
    echo "|       Deployment Complete           |"
    echo "---------------------------------------"
    echo ""
}

# Main execution function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Set variables with hierarchy
    set_variables

    # Validate inputs
    validate_inputs

    # Display configuration
    display_configuration

    if [[ "${TYPE}" == "plan" ]]; then
        echo "---------------------------------------"
        echo "|    Beginning Deployment What-If     |"
        echo "---------------------------------------"
        echo ""
    else
        echo "---------------------------------------"
        echo "|        Beginning Deployment         |"
        echo "---------------------------------------"
        echo ""
    fi

    # Source the Azure CLI login module
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/scripts/azure-cli-login.sh"

    azure_cli_login --client-id "${CLIENT_ID}" --client-secret "${CLIENT_SECRET}" --tenant-id "${TENANT_ID}" --subscription-id "${SUBSCRIPTION_ID}" ${DEBUG_FLAG:+--debug}

    # Handle resource group operations
    handle_resource_group

    # Execute appropriate deployment type
    if [[ "${TYPE}" == "plan" ]]; then
        execute_deployment_plan
    else
        execute_deployment
    fi

}

# Call main function with all arguments
main "$@"
