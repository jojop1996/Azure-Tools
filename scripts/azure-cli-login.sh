#!/bin/bash

######################################
# Azure CLI check and authentication module
# Provides reusable functions for checking Azure CLI installation,
# authentication status, and performing service principal login.
######################################

############### USAGE ################
# ./azure-cli-login-new.sh [options]
# Options:
#   --client-id <id>             Azure Client ID
#   --client-secret <secret>     Azure Client Secret
#   --tenant-id <id>             Azure Tenant ID
#   --subscription-id <id>       Azure Subscription ID (optional)
#   --force-login                Force re-authentication even if already logged in
#   --debug                      Enable debug mode
#   --help                       Display this help message
#
# Examples:
#   ./azure-cli-login-new.sh --client-id "xxx" --client-secret "xxx" --tenant-id "xxx"
#   ./azure-cli-login-new.sh --client-id "xxx" --client-secret "xxx" --tenant-id "xxx" --subscription-id "xxx"
#   ./azure-cli-login-new.sh --force-login --client-id "xxx" --client-secret "xxx" --tenant-id "xxx"
######################################

######### VARIABLE HIERARCHY #########
# 1. Command line arguments (highest priority)
# 2. Environment variables (fallback)
# 3. Default values (lowest priority, where applicable)
#
# Required variables (no defaults):
# - CLIENT_ID
# - CLIENT_SECRET
# - TENANT_ID
######################################

# Set default outputs
DEBUG_OUT="/dev/stdout"
DEBUG_ARG=""

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --client-id <id>             Azure Client ID"
    echo "  --client-secret <secret>     Azure Client Secret"
    echo "  --tenant-id <id>             Azure Tenant ID"
    echo "  --subscription-id <id>       Azure Subscription ID (optional)"
    echo "  --force-login                Force re-authentication even if already logged in"
    echo "  --debug                      Enable debug mode"
    echo "  --help                       Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --client-id \"xxx\" --client-secret \"xxx\" --tenant-id \"xxx\""
    echo "  $0 --client-id \"xxx\" --client-secret \"xxx\" --tenant-id \"xxx\" --subscription-id \"xxx\""
    echo "  $0 --force-login --client-id \"xxx\" --client-secret \"xxx\" --tenant-id \"xxx\""
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_CLIENT_ID              Alternative to --client-id"
    echo "  AZURE_CLIENT_SECRET          Alternative to --client-secret"
    echo "  AZURE_TENANT_ID              Alternative to --tenant-id"
    echo "  AZURE_SUBSCRIPTION_ID        Alternative to --subscription-id"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --client-id)
            ARG_CLIENT_ID="$2"
            shift 2
            ;;
        --client-secret)
            ARG_CLIENT_SECRET="$2"
            shift 2
            ;;
        --tenant-id)
            ARG_TENANT_ID="$2"
            shift 2
            ;;
        --subscription-id)
            ARG_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --force-login)
            FORCE_LOGIN_FLAG=true
            shift
            ;;
        --debug)
            DEBUG_ARG="--debug"
            shift
            ;;
        --help)
            show_help
            exit 0
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
    CLIENT_ID="${ARG_CLIENT_ID:-${AZURE_CLIENT_ID}}"
    CLIENT_SECRET="${ARG_CLIENT_SECRET:-${AZURE_CLIENT_SECRET}}"
    TENANT_ID="${ARG_TENANT_ID:-${AZURE_TENANT_ID}}"

    # Optional variables
    SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}"
    FORCE_LOGIN="${FORCE_LOGIN_FLAG:-false}"
}

# Function to validate inputs
validate_inputs() {
    if [ -z "${CLIENT_ID}" ]; then
        echo "[ERROR] CLIENT_ID is required (provide via --client-id or AZURE_CLIENT_ID environment variable)"
        exit 1
    fi

    if [ -z "${CLIENT_SECRET}" ]; then
        echo "[ERROR] CLIENT_SECRET is required (provide via --client-secret or AZURE_CLIENT_SECRET environment variable)"
        exit 1
    fi

    if [ -z "${TENANT_ID}" ]; then
        echo "[ERROR] TENANT_ID is required (provide via --tenant-id or AZURE_TENANT_ID environment variable)"
        exit 1
    fi
}

# Function to display configuration
display_configuration() {
    echo ""
    echo "Azure CLI Login Configuration"
    echo "---------------------------------------"
    echo ""
    echo "[INFO] CLIENT_ID: ${CLIENT_ID}"
    echo "[INFO] TENANT_ID: ${TENANT_ID}"

    if [ ! -z "${SUBSCRIPTION_ID}" ]; then
        echo "[INFO] SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
    fi

    if [ "${FORCE_LOGIN}" = true ]; then
        echo "[INFO] FORCE_LOGIN: true"
    fi
    echo ""
}

# Function to check if Azure CLI is installed
check_azure_cli_installed() {
    if ! command -v az &>/dev/null; then
        echo "[ERROR] Azure CLI is not installed"
        echo ""
        exit 1
    fi

    echo "[INFO] Azure CLI is installed"
    echo ""
    return 0
}

# Function to check if already authenticated with Azure CLI
check_azure_cli_authenticated() {
    if az account show $DEBUG_ARG >"$DEBUG_OUT" 2>&1; then
        local current_account=$(az account show --query name -o tsv $DEBUG_ARG >"$DEBUG_OUT" 2>&1)
        echo ""
        echo "[INFO] Already authenticated to Azure CLI"
        echo "[INFO] Current account: ${current_account:-Unknown}"
        return 0
    else
        echo ""
        echo "[INFO] Not currently authenticated to Azure CLI"
        return 1
    fi
}

# Function to perform Azure CLI service principal login
login_to_azure() {
    echo "[INFO] Authenticating with Azure CLI using service principal..."
    echo ""

    if az login --service-principal \
        --username "${CLIENT_ID}" \
        --password "${CLIENT_SECRET}" \
        --tenant "${TENANT_ID}" \
        $DEBUG_ARG >"$DEBUG_OUT" 2>&1; then
        echo ""
        echo "[INFO] Authenticated to Azure CLI"
        return 0
    else
        echo ""
        echo "[ERROR] Failed to authenticate with Azure CLI"
        exit 1
    fi
}

# Function to set Azure subscription
set_subscription() {
    echo "[INFO] Setting Azure subscription: ${SUBSCRIPTION_ID}"

    if az account set \
        --subscription "${SUBSCRIPTION_ID}" \
        $DEBUG_ARG >"$DEBUG_OUT" 2>&1; then
        echo "[INFO] Azure subscription set"
        return 0
    else
        echo "[ERROR] Failed to set Azure subscription"
        return 1
    fi
}

# Function to handle authentication logic
handle_authentication() {
    echo "Azure Login"
    echo "---------------------------------------"
    echo ""

    # Check if Azure CLI is installed
    check_azure_cli_installed

    # Check if already authenticated (unless force_login is true)
    if [ "${FORCE_LOGIN}" != "true" ] && check_azure_cli_authenticated; then
        # If subscription_id is provided, ensure we're using the right subscription
        if [ ! -z "${SUBSCRIPTION_ID}" ]; then
            local current_subscription=$(az account show --query id -o tsv $DEBUG_ARG >"$DEBUG_OUT" 2>&1)
            if [ "${current_subscription}" != "${SUBSCRIPTION_ID}" ]; then
                echo "[INFO] Switching to target subscription..."
                set_subscription
            else
                echo "[INFO] Already using target subscription"
            fi
        fi
        return 0
    fi

    # Perform authentication
    login_to_azure

    # Set subscription if provided
    if [ ! -z "${SUBSCRIPTION_ID}" ]; then
        set_subscription
    fi
}

# Main execution function
azure_cli_login() {
    # Parse command line arguments
    parse_arguments "$@"

    # Set variables with hierarchy
    set_variables

    # Validate inputs
    validate_inputs

    # Display configuration
    display_configuration

    # Handle authentication
    handle_authentication
}

# If script is run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    azure_cli_login "$@"
fi
