#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default variables
SECRETS_FILE=".env"
SECRETS_ENCRYPTED_FILE=".env.encrypted"
SECRETS_TEMPLATE_FILE=".env.example"
ACTION="help"
PASSWORD=""

# Help function
function show_help {
    echo -e "${BLUE}CP-Planta Secrets Manager${NC}"
    echo -e "Manages encrypted secrets for the infrastructure deployment"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  ./secrets-manager.sh [ACTION] [OPTIONS]"
    echo ""
    echo -e "${YELLOW}Actions:${NC}"
    echo -e "  encrypt       Encrypt the .env file (requires -p/--password)"
    echo -e "  decrypt       Decrypt the .env.encrypted file (requires -p/--password)"
    echo -e "  template  template    Create a template .env file (will not overwrite existing one)"
    echo -e "  check         Check if all required secrets are present in the .env file"
    echo -e "  help          Show this help message"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -p, --password PASSWORD    Password for encryption/decryption"
    echo -e "  -f, --file FILENAME        Specify an alternative input file (default: .env or .env.encrypted)"
    echo -e "  -o, --output FILENAME      Specify an alternative output file"
    echo -e "  -h, --help                 Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  ./secrets-manager.sh encrypt -p mypassword"
    echo -e "  ./secrets-manager.sh decrypt -p mypassword"
    echo -e "  ./secrets-manager.sh template"
    echo -e "  ./secrets-manager.sh check"
}

# Required secrets for different providers
AWS_REQUIRED_SECRETS=(
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "POSTGRES_DB"
    "PGADMIN_DEFAULT_EMAIL"
    "PGADMIN_DEFAULT_PASSWORD"
    "PGADMIN_LISTEN_PORT"
    "DOMAIN_NAME"
    "ACME_EMAIL"
    "DUCKDNS_TOKEN"
    "DUCKDNS_SUBDOMAIN"
    "TRAEFIK_DASHBOARD_USER"
    "TRAEFIK_DASHBOARD_PASSWORD_HASH"
    "PRIMARY_HOST"
    "REPLICA_HOST"
    "BACKEND_PORT"
    "FRONTEND_PORT"
    "NEXT_PUBLIC_API_URL"
    "TZ"
)

AZURE_REQUIRED_SECRETS=(
    "AZURE_SUBSCRIPTION_ID"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "POSTGRES_DB"
    "PGADMIN_DEFAULT_EMAIL"
    "PGADMIN_DEFAULT_PASSWORD"
    "PGADMIN_LISTEN_PORT"
    "DOMAIN_NAME"
    "ACME_EMAIL"
    "DUCKDNS_TOKEN"
    "DUCKDNS_SUBDOMAIN"
    "TRAEFIK_DASHBOARD_USER"
    "TRAEFIK_DASHBOARD_PASSWORD_HASH"
    "PRIMARY_HOST"
    "REPLICA_HOST"
    "BACKEND_PORT"
    "FRONTEND_PORT"
    "NEXT_PUBLIC_API_URL"
    "TZ"
)

# Parse command line arguments
if [[ $# -lt 1 ]]; then
    show_help
    exit 0
fi

ACTION=$1
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -f|--file)
            SECRETS_FILE="$2"
            shift 2
            ;;
        -o|--output)
            SECRETS_ENCRYPTED_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: OpenSSL is not installed. Please install it before using this script.${NC}"
    exit 1
fi

# Create template function
function create_template {
    if [[ -f "$SECRETS_TEMPLATE_FILE" ]]; then
        echo -e "${YELLOW}Template file $SECRETS_TEMPLATE_FILE already exists.${NC}"
        echo -e "Do you want to overwrite it? (y/N): "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Template creation aborted.${NC}"
            return
        fi
    fi

    cat > "$SECRETS_TEMPLATE_FILE" << 'EOL'
# Azure Provider Credentials
AZURE_SUBSCRIPTION_ID=your_azure_subscription_id

# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=postgres
PRIMARY_HOST=postgres_primary
REPLICA_HOST=postgres_replica

# PgAdmin Configuration
PGADMIN_DEFAULT_EMAIL=your_pgadmin_email@example.com
PGADMIN_DEFAULT_PASSWORD=your_secure_pgadmin_password
PGADMIN_LISTEN_PORT=5050

# Traefik Dashboard Configuration
TRAEFIK_DASHBOARD_USER=admin
TRAEFIK_DASHBOARD_PASSWORD_HASH=$$apr1$$uyBtMQYo$$TMK6XINUQz.mLxjdJsl1j.

# Application Configuration
DOMAIN_NAME=cpplanta.duckdns.com
ACME_EMAIL=your_email@example.com
NEXT_PUBLIC_API_URL=https://api.cpplanta.duckdns.org
BACKEND_PORT=3000
FRONTEND_PORT=3001

# Service Ports
POSTGRES_PRIMARY_PORT=5432
POSTGRES_REPLICA_PORT=5433
PGBOUNCER_PORT=6432
TRAEFIK_DASHBOARD_PORT=8080

# DuckDNS Configuration
DUCKDNS_TOKEN=your_duckdns_token
DUCKDNS_SUBDOMAIN=cpplanta

# Regional Configuration
TZ=America/Sao_Paulo

# AWS Provider Credentials
# Only needed when using actions with AWS provider (add as secrets in GitHub)
# secrets.AWS_ACCESS_KEY_ID
# secrets.AWS_SECRET_ACCESS_KEY

# Optional Configuration
# DOCKER_REGISTRY_URL=registry.example.com
# DOCKER_REGISTRY_USER=registry_user
# DOCKER_REGISTRY_PASS=registry_password
EOL

    echo -e "${GREEN}Template file $SECRETS_TEMPLATE_FILE created successfully.${NC}"
    echo -e "${YELLOW}Fill in your actual values and rename to .env for use.${NC}"
}

# Encrypt function
function encrypt_secrets {
    if [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}Error: Password is required for encryption.${NC}"
        exit 1
    fi

    if [[ ! -f "$SECRETS_FILE" ]]; then
        echo -e "${RED}Error: Secrets file $SECRETS_FILE does not exist.${NC}"
        echo -e "${YELLOW}Create it with required secrets or run 'template' action first.${NC}"
        exit 1
    fi

    # Encrypt the file
    openssl enc -aes-256-cbc -salt -in "$SECRETS_FILE" -out "$SECRETS_ENCRYPTED_FILE" -pass pass:"$PASSWORD"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Secrets file encrypted successfully to $SECRETS_ENCRYPTED_FILE${NC}"
        echo -e "${YELLOW}Keep your password safe. You will need it to decrypt.${NC}"
    else
        echo -e "${RED}Failed to encrypt secrets file.${NC}"
        exit 1
    fi
}

# Decrypt function
function decrypt_secrets {
    if [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}Error: Password is required for decryption.${NC}"
        exit 1
    fi

    if [[ ! -f "$SECRETS_ENCRYPTED_FILE" ]]; then
        echo -e "${RED}Error: Encrypted secrets file $SECRETS_ENCRYPTED_FILE does not exist.${NC}"
        exit 1
    fi

    # Decrypt the file
    openssl enc -aes-256-cbc -d -in "$SECRETS_ENCRYPTED_FILE" -out "$SECRETS_FILE" -pass pass:"$PASSWORD"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Secrets file decrypted successfully to $SECRETS_FILE${NC}"
    else
        echo -e "${RED}Failed to decrypt secrets file. Check your password.${NC}"
        exit 1
    fi
}

# Check secrets function
function check_secrets {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        echo -e "${RED}Error: Secrets file $SECRETS_FILE does not exist.${NC}"
        exit 1
    fi

    # Source the secrets file to evaluate variables
    source "$SECRETS_FILE"

    # Check AWS secrets if using AWS provider
    echo -e "${YELLOW}Checking for AWS provider secrets:${NC}"
    AWS_MISSING=0
    for secret in "${AWS_REQUIRED_SECRETS[@]}"; do
        if [[ -z "${!secret}" ]]; then
            echo -e "${RED}✗ Missing: $secret${NC}"
            AWS_MISSING=$((AWS_MISSING + 1))
        else
            echo -e "${GREEN}✓ Found: $secret${NC}"
        fi
    done

    # Check Azure secrets if using Azure provider
    echo -e "\n${YELLOW}Checking for Azure provider secrets:${NC}"
    AZURE_MISSING=0
    for secret in "${AZURE_REQUIRED_SECRETS[@]}"; do
        if [[ -z "${!secret}" ]]; then
            echo -e "${RED}✗ Missing: $secret${NC}"
            AZURE_MISSING=$((AZURE_MISSING + 1))
        else
            echo -e "${GREEN}✓ Found: $secret${NC}"
        fi
    done

    # Summary
    echo -e "\n${YELLOW}Summary:${NC}"
    if [[ $AWS_MISSING -eq 0 ]]; then
        echo -e "${GREEN}All AWS provider secrets found.${NC}"
    else
        echo -e "${RED}Missing $AWS_MISSING AWS provider secrets.${NC}"
    fi

    if [[ $AZURE_MISSING -eq 0 ]]; then
        echo -e "${GREEN}All Azure provider secrets found.${NC}"
    else
        echo -e "${RED}Missing $AZURE_MISSING Azure provider secrets.${NC}"
    fi

    # Check for credentials to determine which provider can be used
    if [[ $AWS_MISSING -eq 0 && $AZURE_MISSING -gt 0 ]]; then
        echo -e "\n${GREEN}You can use the AWS provider with these credentials.${NC}"
    elif [[ $AZURE_MISSING -eq 0 && $AWS_MISSING -gt 0 ]]; then
        echo -e "\n${GREEN}You can use the Azure provider with these credentials.${NC}"
    elif [[ $AWS_MISSING -eq 0 && $AZURE_MISSING -eq 0 ]]; then
        echo -e "\n${GREEN}You can use either AWS or Azure provider with these credentials.${NC}"
    else
        echo -e "\n${RED}You don't have all required credentials for any provider.${NC}"
        echo -e "${YELLOW}Please update your $SECRETS_FILE file with the missing secrets.${NC}"
        exit 1
    fi
}

# Execute requested action
case "$ACTION" in
    encrypt)
        encrypt_secrets
        ;;
    decrypt)
        decrypt_secrets
        ;;
    template)
        create_template
        ;;
    check)
        check_secrets
        ;;
    help|*)
        show_help
        ;;
esac

exit 0