#!/bin/bash

######################################
# Azure Resource Group management module
# Provides reusable functions for checking, creating, and deleting
# Azure resource groups.
######################################

############### USAGE ################
# ./azure-resource-group.sh [options]
# Options:
#   --action <action>            Action to perform: check, create, delete (required)
#   --resource-group-name <name> Resource group name (required)
#   --location <location>        Azure region (default: eastus)
#   --subscription-id <id>       Azure Subscription ID (optional)
#   --yes                        Skip confirmation for delete operation
#   --debug                      Enable debug mode
#   --help                       Display this help message
#
# Examples:
#   ./azure-resource-group.sh --action check --resource-group-name "my-rg"
#   ./azure-resource-group.sh --action create --resource-group-name "my-rg" --location "westus2"
#   ./azure-resource-group.sh --action delete --resource-group-name "my-rg" --yes
######################################

######### VARIABLE HIERARCHY #########
# 1. Command line arguments (highest priority)
# 2. Environment variables (fallback)
# 3. Default values (lowest priority, where applicable)
#
# Required variables (no defaults):
# - RESOURCE_GROUP_NAME
# - ACTION
######################################

# Set default outputs
DEBUG_OUT="/dev/stdout"
DEBUG_ARG=""

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --resource-group-name <name> Resource group name (required)"
    echo "  --action <action>            Action to perform: check, create, delete (required)"
    echo "  --location <location>        Azure region (default: eastus)"
    echo "  --subscription-id <id>       Azure Subscription ID (optional)"
    echo "  --yes                        Skip confirmation for delete operation"
    echo "  --debug                      Enable debug mode"
    echo "  --help                       Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --action check --resource-group-name \"my-rg\""
    echo "  $0 --action create --resource-group-name \"my-rg\" --location \"westus2\""
    echo "  $0 --action delete --resource-group-name \"my-rg\" --yes"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_RESOURCE_GROUP_NAME    Alternative to --resource-group-name"
    echo "  AZURE_LOCATION               Alternative to --location"
    echo "  AZURE_SUBSCRIPTION_ID        Alternative to --subscription-id"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --action)
            ARG_ACTION="$2"
            shift 2
            ;;
        --resource-group-name)
            ARG_RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --location)
            ARG_LOCATION="$2"
            shift 2
            ;;
        --subscription-id)
            ARG_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --yes)
            YES_FLAG=true
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
    RESOURCE_GROUP_NAME="${ARG_RESOURCE_GROUP_NAME:-${AZURE_RESOURCE_GROUP_NAME}}"
    ACTION="${ARG_ACTION}"

    # Optional variables with defaults
    LOCATION="${ARG_LOCATION:-${AZURE_LOCATION:-"eastus"}}"
    SUBSCRIPTION_ID="${ARG_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}"
    YES_FLAG="${YES_FLAG:-false}"
}

# Function to validate inputs
validate_inputs() {
    if [ -z "${RESOURCE_GROUP_NAME}" ]; then
        echo "[ERROR] Resource group name is required (provide via --resource-group-name or AZURE_RESOURCE_GROUP_NAME environment variable)"
        exit 1
    fi

    if [ -z "${ACTION}" ]; then
        echo "[ERROR] Action is required (provide via --action: check, create, or delete)"
        exit 1
    fi

    if [[ "${ACTION}" != "check" && "${ACTION}" != "create" && "${ACTION}" != "delete" ]]; then
        echo "[ERROR] Invalid action: ${ACTION}. Must be one of: check, create, delete"
        exit 1
    fi

    if [[ "${ACTION}" == "create" && -z "${LOCATION}" ]]; then
        echo "[ERROR] Location is required for create action (provide via --location or AZURE_LOCATION environment variable)"
        exit 1
    fi
}

# Function to display configuration
display_configuration() {
    echo ""
    echo "Azure Resource Group Configuration"
    echo "---------------------------------------"
    echo ""
    echo "[INFO] ACTION: ${ACTION}"
    echo "[INFO] RESOURCE_GROUP_NAME: ${RESOURCE_GROUP_NAME}"

    echo "[INFO] LOCATION: ${LOCATION}"

    if [ ! -z "${SUBSCRIPTION_ID}" ]; then
        echo "[INFO] SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
    fi

    if [ "${YES_FLAG}" = true ]; then
        echo "[INFO] YES_FLAG: true"
    fi
    echo ""
}

# Function to check if a resource group exists
check_resource_group() {
    echo "[INFO] Checking if resource group '${RESOURCE_GROUP_NAME}' exists..."
    echo ""

    # This is strange because I suppress the error message if a resource group does not exist and debug is false
    if az group show --name "${RESOURCE_GROUP_NAME}" ${SUBSCRIPTION_ID:+--subscription "${SUBSCRIPTION_ID}"} $DEBUG_ARG >"$DEBUG_OUT" 2>$([ -n "$DEBUG_ARG" ] && echo "$DEBUG_OUT" || echo "/dev/null"); then
        echo ""
        echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' exists."
        return 0
    else
        echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' does not exist."
        return 1
    fi
}

# Function to create a resource group
create_resource_group() {
    echo "[INFO] Creating resource group '${RESOURCE_GROUP_NAME}' in location '${LOCATION}'..."
    echo ""
    if az group create \
        --name "${RESOURCE_GROUP_NAME}" \
        --location "${LOCATION}" \
        ${SUBSCRIPTION_ID:+--subscription "${SUBSCRIPTION_ID}"} \
        $DEBUG_ARG >"$DEBUG_OUT" 2>&1; then
        echo ""
        echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' created successfully."
        return 0
    else
        echo "[ERROR] Failed to create resource group '${RESOURCE_GROUP_NAME}'."
        return 1
    fi
}

# Function to delete a resource group
delete_resource_group() {
    echo "[INFO] Deleting resource group '${RESOURCE_GROUP_NAME}'..."

    local confirm_flag=""
    if [ "${YES_FLAG}" = true ]; then
        confirm_flag="--yes"
    fi
    
    echo ""

    if az group delete \
        --name "${RESOURCE_GROUP_NAME}" \
        ${confirm_flag} \
        ${SUBSCRIPTION_ID:+--subscription "${SUBSCRIPTION_ID}"} \
        $DEBUG_ARG >"$DEBUG_OUT" 2>&1; then

        echo "[INFO] Resource group '${RESOURCE_GROUP_NAME}' deleted successfully."
        return 0
    else
        echo ""
        echo "[ERROR] Failed to delete resource group '${RESOURCE_GROUP_NAME}'."
        return 1
    fi
}

# Function to handle resource group operations
handle_resource_group() {
    echo "Azure Resource Group Management"
    echo "---------------------------------------"
    echo ""

    case "${ACTION}" in
    "check")
        check_resource_group
        return $?
        ;;
    "create")
        if ! check_resource_group; then
            create_resource_group
            return $?
        else
            echo "[INFO] Resource group already exists. No action taken."
            return 0
        fi
        ;;
    "delete")
        if check_resource_group; then
            delete_resource_group
            return $?
        else
            echo "[INFO] Resource group does not exist. No action taken."
            return 0
        fi
        ;;
    esac
}

# Main execution function
azure_resource_group() {
    # Parse command line arguments
    parse_arguments "$@"

    # Set variables with hierarchy
    set_variables

    # Validate inputs
    validate_inputs

    # Display configuration
    display_configuration

    # Handle resource group operations
    handle_resource_group
}

# If script is run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    azure_resource_group "$@"
fi
