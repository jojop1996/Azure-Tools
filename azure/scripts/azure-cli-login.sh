#!/bin/bash

######################################
# Azure CLI check and authentication module
# Provides reusable functions for checking Azure CLI installation,
# authentication status, and performing service principal login.
######################################

# Function to check if Azure CLI is installed
check_azure_login_installed() {
  if ! command -v az &>/dev/null; then
    echo "[ERROR] Azure CLI is not installed"
    echo "[INFO] Install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi

  echo "[INFO] Azure CLI is installed"
  return 0
}

# Function to check if already authenticated with Azure CLI
check_azure_login_authenticated() {
  if az account show &>/dev/null; then
    local current_account=$(az account show --query name -o tsv 2>/dev/null)
    echo "[INFO] Already authenticated to Azure CLI"
    echo "[INFO] Current account: ${current_account:-Unknown}"
    return 0
  else
    echo "[INFO] Not currently authenticated to Azure CLI"
    return 1
  fi
}

# Function to perform Azure CLI service principal login
execute_azure_cli_login() {
  local client_id=""
  local client_secret=""
  local tenant_id=""
  local debug_flag=""

  while [[ $# -gt 0 ]]; do
    case $1 in
    --client-id)
      client_id="$2"
      shift 2
      ;;
    --client-secret)
      client_secret="$2"
      shift 2
      ;;
    --tenant-id)
      tenant_id="$2"
      shift 2
      ;;
    --debug)
      debug_flag=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      return 1
      ;;
    esac
  done

  if [ -z "${client_id}" ] || [ -z "${client_secret}" ] || [ -z "${tenant_id}" ]; then
    echo "[ERROR] Azure service principal credentials are required"
    echo "[INFO] Provide client_id, client_secret, and tenant_id"
    return 1
  fi

  echo "[INFO] Authenticating with Azure CLI using service principal..."
  echo ""

  # Login using service principal
  if az login --service-principal \
    --username "${client_id}" \
    --password "${client_secret}" \
    --tenant "${tenant_id}" \
    ${debug_flag:+--debug}; then
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
set_azure_subscription() {
  local subscription_id=""
  local debug_flag=""

  while [[ $# -gt 0 ]]; do
    case $1 in
    --subscription-id)
      subscription_id="$2"
      shift 2
      ;;
    --debug)
      debug_flag=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      return 1
      ;;
    esac
  done

  if [ -z "${subscription_id}" ]; then
    echo "[ERROR] Subscription ID is required"
    return 1
  fi

  echo "[INFO] Setting Azure subscription: ${subscription_id}"

  if az account set \
    --subscription "${subscription_id}" \
    ${debug_flag:+--debug}; then
    echo "[INFO] Azure subscription set"
    return 0
  else
    echo "[ERROR] Failed to set Azure subscription"
    return 1
  fi
}

# Main function that combines all checks and authentication
azure_cli_login() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --client-id)
      local client_id="$2"
      shift 2
      ;;
    --client-secret)
      local client_secret="$2"
      shift 2
      ;;
    --tenant-id)
      local tenant_id="$2"
      shift 2
      ;;
    --subscription-id)
      local subscription_id="$2"
      shift 2
      ;;
    --force-login)
      local force_login="${2:-false}"
      shift 2
      ;;
    --debug)
      local debug_flag=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
    esac
  done

  echo "Azure Login"
  echo "---------------------------------------"
  echo ""

  # Check if Azure CLI is installed
  if ! check_azure_login_installed; then
    return 1
  fi

  # Check if already authenticated (unless force_login is true)
  if [ "${force_login}" != "true" ] && check_azure_login_authenticated; then
    # If subscription_id is provided, ensure we're using the right subscription
    if [ ! -z "${subscription_id}" ]; then
      local current_subscription=$(az account show --query id -o tsv 2>/dev/null)
      if [ "${current_subscription}" != "${subscription_id}" ]; then
        echo "[INFO] Switching to target subscription..."
        set_azure_subscription --subscription-id "${subscription_id}" ${debug_flag:+--debug}
      else
        echo "[INFO] Already using target subscription"
      fi
    fi
    return 0
  fi

  # Perform authentication
  if ! execute_azure_cli_login --client-id "${client_id}" --client-secret "${client_secret}" --tenant-id "${tenant_id}" ${debug_flag:+--debug}; then
    return 1
  fi

  # Set subscription if provided
  if [ ! -z "${subscription_id}" ]; then
    if ! set_azure_subscription --subscription-id "${subscription_id}" ${debug_flag:+--debug}; then
      return 1
    fi
  fi

  return 0
}

# If script is run directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Azure CLI Login Module"
  echo "Usage: source azure-cli-login.sh"
  echo ""
  echo "Available functions:"
  echo "  check_azure_login_installed         - Check if Azure CLI is installed"
  echo "  check_azure_login_authenticated     - Check if already authenticated"
  echo "  execute_azure_cli_login --client-id <id> --client-secret <secret> --tenant-id <tenant> [--debug] - Perform service principal login"
  echo "  set_azure_subscription --subscription-id <sub_id> [--debug] - Set Azure subscription"
  echo "  azure_cli_login --client-id <id> --client-secret <secret> --tenant-id <tenant> [--subscription-id <sub_id>] [--debug] [--force-login <true|false>] - Complete check and auth"
  echo ""
  echo "Example:"
  echo "  source azure-cli-login.sh"
  echo "  azure_cli_login --client-id \"\${CLIENT_ID}\" --client-secret \"\${CLIENT_SECRET}\" --tenant-id \"\${TENANT_ID}\" --subscription-id \"\${SUBSCRIPTION_ID}\" --debug"
fi
