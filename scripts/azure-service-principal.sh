#!/bin/bash

######################################
# Service Principal Management Script
#
# Usage:
#   ./service-principal.sh --action <create|destroy> --tenant-id <id> --scope <scope> --sp-name <name> [--role <role1>] [--role <role2>] ...
#
# Environment Variables:
#   SP_ACTION, SP_TENANT_ID, SP_SCOPE, SP_NAME, SP_ROLE (comma-separated)
#
# Examples:
#   ./service-principal.sh --action create --tenant-id <id> --scope "/subscriptions/xxxx" --sp-name "my-sp" --role "Contributor" --role "Reader"
#   ./service-principal.sh --action create --tenant-id <id> --scope "/subscriptions/xxxx" --sp-name "my-sp"
#   ./service-principal.sh --action destroy --tenant-id <id> --sp-name "my-sp"
######################################

# Function to display help message
show_help() {
    echo ""
    echo "Usage: $0 --action <create|destroy> --tenant-id <id> --scope <scope> --sp-name <name> [--role <role1>] [--role <role2>] ..."
    echo ""
    echo "Options:"
    echo "  --action <create|destroy>    Action to perform (required)"
    echo "  --tenant-id <tenant_id>      Azure AD Tenant ID (required)"
    echo "  --scope <scope>              Scope for role assignment (required for create)"
    echo "  --sp-name <name>             Service Principal name (required)"
    echo "  --role <role>                Role to assign (can be specified multiple times, only for create)"
    echo "  --help                       Display this help message"
    echo ""
    echo "Environment Variables:"
    echo "  SP_ACTION, SP_TENANT_ID, SP_SCOPE, SP_NAME, SP_ROLE (comma-separated)"
    echo ""
    echo "Examples:"
    echo "  $0 --action create --tenant-id <id> --scope \"/subscriptions/xxxx\" --sp-name \"my-sp\" --role \"Contributor\" --role \"Reader\""
    echo "  $0 --action create --tenant-id <id> --scope \"/subscriptions/xxxx\" --sp-name \"my-sp\""
    echo "  $0 --action destroy --tenant-id <id> --sp-name \"my-sp\""
    echo ""
    echo "Note: If both --role and SP_ROLE are set, command-line arguments take precedence."
    echo ""
}

# Parse arguments
ROLE_LIST=()
ROLE_ARG_SET=false
while [[ $# -gt 0 ]]; do
    case $1 in
    --action)
        ARG_ACTION="$2"
        shift 2
        ;;
    --tenant-id)
        ARG_TENANT_ID="$2"
        shift 2
        ;;
    --scope)
        ARG_SCOPE="$2"
        shift 2
        ;;
    --sp-name)
        ARG_SP_NAME="$2"
        shift 2
        ;;
    --role)
        ROLE_LIST+=("$(echo "$2" | xargs)")
        ROLE_ARG_SET=true
        shift 2
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

# Set variables with hierarchy (args > env > defaults)
ACTION="${ARG_ACTION:-${SP_ACTION}}"
TENANT_ID="${ARG_TENANT_ID:-${SP_TENANT_ID}}"
SCOPE="${ARG_SCOPE:-${SP_SCOPE}}"
SP_NAME="${ARG_SP_NAME:-${SP_NAME:-${SP_NAME}}}"

# Validate required arguments
if [[ -z "$ACTION" || -z "$SP_NAME" ]]; then
    echo ""
    echo "[ERROR] --action and --sp-name are required (or set SP_ACTION/SP_NAME env vars)."
    show_help
    exit 1
fi

# Validate required arguments
if [[ -z "$TENANT_ID" ]]; then
    echo ""
    echo "[ERROR] --tenant-id is required (or set SP_TENANT_ID env var)."
    show_help
    exit 1
fi

# Validate role input and prioritize command-line args
if [[ ${#ROLE_LIST[@]} -eq 0 ]]; then
    if [[ -n "$SP_ROLE" ]]; then
        # Only comma-separated supported for env
        IFS=',' read -ra RAW_ROLES <<<"$SP_ROLE"
        for r in "${RAW_ROLES[@]}"; do
            ROLE_LIST+=("$(echo "$r" | xargs)")
        done
    else
        ROLE_LIST=("Contributor")
    fi
elif [[ -n "$SP_ROLE" ]]; then
    echo ""
    echo "---------------------------------------"
    echo "WARNING: Both --role and SP_ROLE are set."
    echo "Command-line arguments will be used for role assignment."
    echo "---------------------------------------"
fi

# Build desired roles associative array
declare -A DESIRED_ROLES
for r in "${ROLE_LIST[@]}"; do
    DESIRED_ROLES["$r"]=1
done

# Prompt user for Azure CLI login
echo ""
echo "Configuring Azure CLI..."
az config set core.login_experience_v2=off

echo ""
echo "Logging into the Azure CLI..."
echo "---------------------------------------"
echo ""

az login --tenant "$TENANT_ID" --only-show-errors
if [ $? -ne 0 ]; then
    echo ""
    echo "[ERROR] Azure CLI login failed."
    exit 1
fi

if [[ "$ACTION" == "create" ]]; then
    echo ""
    echo "---------------------------------------"
    echo "Service Principal Creation"
    echo "---------------------------------------"
    # Check if SP exists
    EXISTING_SP=$(az ad sp list --display-name "$SP_NAME" --query "[].appId" -o tsv)
    if [ -n "$EXISTING_SP" ]; then
        echo ""
        echo "Service Principal '$SP_NAME' already exists with App ID: $EXISTING_SP"
        APP_ID="$EXISTING_SP"
        # Ensure scope is provided
        if [[ -z "$SCOPE" ]]; then
            echo ""
            echo "[ERROR] --scope is required for role assignment."
            exit 1
        fi
        # Get current role assignments at the specified scope
        CURRENT_ROLES_RAW=()
        while IFS= read -r line; do
            CURRENT_ROLES_RAW+=("$line")
        done < <(az role assignment list --assignee "$APP_ID" --scope "$SCOPE" --query "[].roleDefinitionName" -o tsv)
        declare -A CURRENT_ROLES
        for cr in "${CURRENT_ROLES_RAW[@]}"; do
            CLEAN_CR="$(echo "$cr" | xargs)"
            CURRENT_ROLES["$CLEAN_CR"]=1
        done
        # Remove roles not specified in --role
        for cr in "${!CURRENT_ROLES[@]}"; do
            if [[ -z "${DESIRED_ROLES[$cr]}" ]]; then
                echo ""
                echo "Removing role assignment: $cr"
                az role assignment delete --assignee "$APP_ID" --role "$cr" --scope "$SCOPE"
            fi
        done
        # Add roles specified in --role that are missing
        for r in "${!DESIRED_ROLES[@]}"; do
            if [[ -z "${CURRENT_ROLES[$r]}" ]]; then
                echo ""
                echo "Assigning missing role: $r"
                echo ""
                az role assignment create --assignee "$APP_ID" --role "$r" --scope "$SCOPE"
            fi
        done
        # Confirm Role Assignment
        ASSIGNED_ROLES=$(az role assignment list --assignee "$APP_ID" --scope "$SCOPE" --query "[].roleDefinitionName" -o tsv)
        echo ""
        echo "Assigned Roles"
        echo "---------------------------------------"
        echo ""
        echo "$ASSIGNED_ROLES"
        echo ""
        exit 0
    fi

    # Create SP
    echo ""
    echo "Creating Service Principal..."
    echo ""
    SP_OUTPUT=$(az ad sp create-for-rbac --name "$SP_NAME" --role "${ROLE_LIST[0]}" --scopes "$SCOPE")
    # Assign additional roles if specified
    APP_ID=$(echo "$SP_OUTPUT" | jq -r .appId)
    for r in "${ROLE_LIST[@]:1}"; do
        echo ""
        echo "Assigning additional role: $r"
        echo ""
        az role assignment create --assignee "$APP_ID" --role "$r" --scope "$SCOPE"
    done

    # Confirm Role Assignment
    ASSIGNED_ROLES=$(az role assignment list --assignee "$APP_ID" --query "[].roleDefinitionName" -o tsv)
    echo ""
    echo "Assigned Roles"
    echo "---------------------------------------"
    echo ""
    echo "$ASSIGNED_ROLES"
    echo ""

    DISPLAY_NAME=$(echo "$SP_OUTPUT" | jq -r .displayName)
    PASSWORD=$(echo "$SP_OUTPUT" | jq -r .password)
    TENANT=$(echo "$SP_OUTPUT" | jq -r .tenant)

    echo "Service Principal Details (${DISPLAY_NAME})"
    echo "---------------------------------------"
    echo ""
    echo "export AZURE_CLIENT_ID=\"${APP_ID}\""
    echo "export AZURE_CLIENT_SECRET=\"${PASSWORD}\""
    echo "export AZURE_TENANT_ID=\"${TENANT}\""
    echo ""

elif [[ "$ACTION" == "destroy" ]]; then
    echo ""
    echo "---------------------------------------"
    echo "Service Principal Deletion"
    echo "---------------------------------------"
    # Get App ID
    APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv)
    if [ -z "$APP_ID" ]; then
        echo ""
        echo "No Service Principal found with name '$SP_NAME'."
        exit 1
    fi

    echo ""
    echo "Found App ID: $APP_ID"
    echo ""
    # Remove role assignments
    echo "Removing role assignments..."
    ASSIGNMENTS=$(az role assignment list --assignee "$APP_ID" --query "[].id" -o tsv)
    for ROLE_ID in $ASSIGNMENTS; do
        az role assignment delete --ids "$ROLE_ID"
        echo "Deleted role assignment: $ROLE_ID"
    done

    # Delete Service Principal (Enterprise App)
    echo ""
    echo "Deleting Service Principal..."
    az ad sp delete --id "$APP_ID"
    echo "Deleted Service Principal: $APP_ID"
    # Delete App Registration
    echo ""
    echo "Deleting App Registration..."
    APP_OBJECT_ID=$(az ad app list --app-id "$APP_ID" --query "[0].id" -o tsv)
    if [ -n "$APP_OBJECT_ID" ]; then
        az ad app delete --id "$APP_OBJECT_ID"
        echo "Deleted App Registration: $APP_OBJECT_ID"
    else
        echo "App Registration not found or already deleted."
    fi

    echo ""
    echo "Cleanup complete for '$SP_NAME'"
    echo ""
else
    echo ""
    echo "[ERROR] Unknown action: $ACTION"
    show_help
    exit 1
fi
