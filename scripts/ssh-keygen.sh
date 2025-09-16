#!/bin/bash

######################################
# Automates SSH key generation.
# Generates a single RSA 4096-bit key pair.
######################################

############### USAGE ################
# ./ssh-keygen.sh [options]
# Options:
#   --key-path <path>              Path for generated keys
#   --key-name <name>              Name for generated keys
#   --force                        Force regeneration even if keys exist
#   --debug                        Enable debug mode
#   --help                         Display this help message
######################################

# Function to display help message
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --key-path <path>              Path for generated keys"
    echo "  --key-name <name>              Name for generated keys"
    echo "  --force                        Force regeneration even if keys exist"
    echo "  --debug                        Enable debug mode"
    echo "  --help                         Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --key-path test-keys --key-name test_deploy --force"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --key-path)
            ARG_SSH_KEY_PATH="$2"
            shift 2
            ;;
        --key-name)
            ARG_KEY_NAME="$2"
            shift 2
            ;;
        --key-comment)
            ARG_KEY_COMMENT="$2"
            shift 2
            ;;
        --force)
            FORCE_REGENERATE=true
            shift
            ;;
        --debug)
            DEBUG_FLAG=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
        esac
    done
}

# Function to set variables with hierarchy
set_variables() {

    SSH_KEY_PATH="${ARG_SSH_KEY_PATH:-${SSH_KEY_PATH:-"keys"}}"
    SSH_KEY_NAME="${ARG_SSH_KEY_NAME:-${SSH_KEY_NAME:-"id_rsa"}}"
    SSH_KEY_COMMENT="${ARG_SSH_KEY_COMMENT:-${SSH_KEY_COMMENT:-"ssh-public-key"}}"
}

# Function to generate SSH key pair
generate_ssh_keys() {
    # Check if keys already exist
    if [ -f "${SSH_KEY_PATH}/${SSH_KEY_NAME}" ]; then
        if [ "${FORCE_REGENERATE}" = true ]; then
            echo "[INFO] Force regeneration enabled, removing existing keys..."
            rm "${SSH_KEY_PATH}/${SSH_KEY_NAME}" "${SSH_KEY_PATH}/${SSH_KEY_NAME}.pub"
        else
            echo "[INFO] SSH keys already exist"
            echo "[INFO] Use --force to replace them"
            return 0
        fi
    fi

    # Create key directory
    mkdir -p "${SSH_KEY_PATH}" || {
        echo "[ERROR] Failed to create directory: ${SSH_KEY_PATH}"
        exit 1
    }

    echo "[INFO] Generating SSH key pair..."
    # Generate the key pair
    if ssh-keygen -t rsa -b 4096 -C "${SSH_KEY_COMMENT}" -f "${SSH_KEY_PATH}/${SSH_KEY_NAME}" -N "" >/dev/null 2>&1; then
        echo "[INFO] SSH key pair generated successfully"
        echo "  Private key: ${SSH_KEY_NAME}"
        echo "  Public key:  ${SSH_KEY_NAME}.pub"
        echo ""

        # Set proper permissions
        chmod 600 "${SSH_KEY_PATH}/${SSH_KEY_NAME}"
        chmod 644 "${SSH_KEY_PATH}/${SSH_KEY_NAME}.pub"

        return 0
    else
        echo "[ERROR] Failed to generate SSH key pair"
        return 1
    fi
}

ssh_keygen() {
    # Parse command line arguments
    parse_arguments "$@"

    # Set variables with hierarchy
    set_variables

    # Main execution logic
    if ! generate_ssh_keys; then
        echo "[ERROR] Key generation failed"
        exit 1
    fi

    echo "[INFO] SSH key management complete!"
}

ssh_keygen "$@"
