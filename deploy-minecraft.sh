#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROVIDER="aws"
SKIP_TERRAFORM=false
INTERACTIVE=true
DEPLOYMENT_LOG="minecraft_deployment_$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_ENABLED=true
MINECRAFT_VERSION="latest"
MINECRAFT_MODE="survival"
MINECRAFT_DIFFICULTY="normal"
USE_BEDROCK=true

# Create log file
touch $DEPLOYMENT_LOG
exec > >(tee -a $DEPLOYMENT_LOG)
exec 2>&1

# Export environment variables for Ansible and Python
export ANSIBLE_FORCE_COLOR=true
export PYTHONIOENCODING=utf-8
export ANSIBLE_HOST_KEY_CHECKING=False

# Add this block to load environment variables globally:
if [[ -f ".env" ]]; then
    echo -e "${YELLOW}Loading environment variables from .env file...${NC}"
    set -o allexport
    source .env
    set +o allexport
else
    echo -e "${YELLOW}No .env file found. Using default values.${NC}"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "==========================================="
echo "Mineclifford Deployment - $(date)"
echo "==========================================="

# Function to show help
function show_help {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -p, --provider <aws|azure>       Specify the cloud provider (default: aws)"
    echo -e "  -s, --skip-terraform             Skip Terraform provisioning"
    echo -e "  -v, --minecraft-version VERSION  Specify Minecraft version (default: latest)"
    echo -e "  -m, --mode <survival|creative>   Game mode (default: survival)"
    echo -e "  -d, --difficulty <peaceful|easy|normal|hard> Game difficulty (default: normal)"
    echo -e "  -b, --no-bedrock                 Skip Bedrock Edition deployment"
    echo -e "      --no-interactive             Run in non-interactive mode"
    echo -e "      --no-rollback                Disable rollback on failure"
    echo -e "  -h, --help                       Show this help message"
    echo -e "${YELLOW}Example:${NC}"
    echo -e "  $0 --provider aws --minecraft-version 1.19 --mode creative"
    exit 0
}

# Function for error handling
function handle_error {
    local exit_code=$?
    local error_message=$1
    local step=$2
    
    echo -e "${RED}ERROR: $error_message (Exit Code: $exit_code)${NC}" 
    echo -e "${RED}Deployment failed during step: $step${NC}"
    
    if [[ "$ROLLBACK_ENABLED" == "true" && "$step" != "pre-deployment" ]]; then
        echo -e "${YELLOW}Initiating rollback procedure...${NC}"
        
        case "$step" in
            "terraform")
                echo -e "${YELLOW}Rolling back infrastructure changes...${NC}"
                if [[ "$PROVIDER" == "aws" ]]; then
                    cd terraform/aws
                elif [[ "$PROVIDER" == "azure" ]]; then
                    cd terraform/azure
                fi
                terraform destroy -auto-approve -target=$(terraform state list | tail -n 1)
                cd ../..
                ;;
            "ansible")
                echo -e "${YELLOW}Cannot automatically rollback Ansible changes.${NC}"
                echo -e "${YELLOW}Manual intervention may be required.${NC}"
                ;;
            "swarm")
                echo -e "${YELLOW}Rolling back Docker Swarm deployment...${NC}"
                # Get manager node from inventory
                MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
                if [[ -n "$MANAGER_IP" ]]; then
                    echo -e "${YELLOW}Connecting to manager node $MANAGER_IP...${NC}"
                    ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker stack rm Mineclifford"
                fi
                ;;
        esac
    fi
    
    echo -e "${YELLOW}See log file for details: $DEPLOYMENT_LOG${NC}"
    exit 1
}

# Pre-deployment validation
function validate_environment {
    echo -e "${BLUE}Validating deployment environment...${NC}"
    
    # Check required tools
    for cmd in terraform ansible-playbook jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: Required tool '$cmd' is not installed.${NC}"
            handle_error "Missing required tool: $cmd" "pre-deployment"
        fi
    done
    
    # Check provider-specific tools
    if [[ "$PROVIDER" == "aws" ]]; then
        if ! command -v aws &> /dev/null; then
            echo -e "${RED}Error: AWS CLI is not installed.${NC}"
            handle_error "Missing required tool: aws" "pre-deployment"
        fi
        echo -e "${YELLOW}Validating AWS credentials...${NC}"
        if ! aws sts get-caller-identity &> /dev/null; then
            handle_error "Invalid AWS credentials" "pre-deployment"
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        if ! command -v az &> /dev/null; then
            echo -e "${RED}Error: Azure CLI is not installed.${NC}"
            handle_error "Missing required tool: az" "pre-deployment"
        fi
        # Using the Terraform prefix(TF_VAR) on var for Azure 
        if [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
            export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
        fi
        
        echo -e "${YELLOW}Validating Azure credentials...${NC}"
        if ! az account show &> /dev/null; then
            handle_error "Invalid Azure credentials" "pre-deployment"
        fi
    fi

    echo -e "${GREEN}Environment validation passed.${NC}"
}

# Run Terraform with error handling
function run_terraform {
    echo -e "${BLUE}Running Terraform for $PROVIDER...${NC}"
    
    if [[ "$PROVIDER" == "aws" ]]; then
        cd terraform/aws
    elif [[ "$PROVIDER" == "azure" ]]; then
        cd terraform/azure
    fi
    
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init || handle_error "Terraform initialization failed" "terraform"
    
    echo -e "${YELLOW}Planning Terraform changes...${NC}"
    terraform plan -out=tf.plan || handle_error "Terraform plan failed" "terraform"
    
    echo -e "${YELLOW}Applying Terraform changes...${NC}"
    terraform apply tf.plan || handle_error "Terraform apply failed" "terraform"
    
    # Save Terraform state
    echo -e "${YELLOW}Saving Terraform state...${NC}"
    if [[ -d "../../.git" ]]; then
        mkdir -p ../../terraform-state
        cp terraform.tfstate ../../terraform-state/terraform-${PROVIDER}-$(date +%Y%m%d).tfstate
    fi
    
    cd ../..
    echo -e "${GREEN}Terraform execution completed successfully.${NC}"
    
    echo -e "${YELLOW}Waiting for instances to initialize (30 seconds)...${NC}"
    for i in {1..30}; do
        echo -n "."
        sleep 1
        if (( i % 10 == 0 )); then
            echo " $i seconds"
        fi
    done
    echo ""
}

# Run Ansible with error handling
function run_ansible {
    echo -e "${BLUE}Running Ansible playbooks for Minecraft...${NC}"
    
    # Verify inventory file exists
    if [[ ! -f "static_ip.ini" ]]; then
        handle_error "Inventory file static_ip.ini not found" "ansible"
    fi
    
    # Set proper permissions for SSH keys
    echo -e "${YELLOW}Setting SSH key permissions...${NC}"
    chmod 400 ssh_keys/*.pem
    
    # Create vars file for Ansible
    echo -e "${YELLOW}Creating Minecraft configuration vars...${NC}"
    cat > deployment/ansible/minecraft_vars.yml << EOF
---
# Minecraft Configuration Variables
minecraft_java_version: "$MINECRAFT_VERSION"
minecraft_java_memory: "2G"
minecraft_java_gamemode: "$MINECRAFT_MODE"
minecraft_java_difficulty: "$MINECRAFT_DIFFICULTY"
minecraft_java_motd: "Mineclifford Java Server"
minecraft_java_allow_nether: true
minecraft_java_enable_command_block: true
minecraft_java_spawn_protection: 0
minecraft_java_view_distance: 10

# Bedrock Edition (if enabled)
minecraft_bedrock_enabled: $USE_BEDROCK
minecraft_bedrock_version: "$MINECRAFT_VERSION"
minecraft_bedrock_memory: "1G"
minecraft_bedrock_gamemode: "$MINECRAFT_MODE"
minecraft_bedrock_difficulty: "$MINECRAFT_DIFFICULTY"
minecraft_bedrock_server_name: "Mineclifford Bedrock Server"
minecraft_bedrock_allow_cheats: false

# Monitoring Configuration
rcon_password: "minecraft"
grafana_password: "admin"
timezone: "America/Sao_Paulo"
EOF
    
    # Run Ansible playbook
    echo -e "${YELLOW}Deploying Minecraft infrastructure via Ansible...${NC}"
    cd deployment/ansible
    
    # Test connectivity
    echo -e "${YELLOW}Testing connectivity to hosts...${NC}"
    ansible -i ../../static_ip.ini all -m ping || handle_error "Ansible connectivity test failed" "ansible"
    
    # Run main playbook
    echo -e "${YELLOW}Running Minecraft setup playbook...${NC}"
    ansible-playbook -i ../../static_ip.ini minecraft_setup.yml -e "@minecraft_vars.yml" || handle_error "Ansible playbook execution failed" "ansible"
    
    cd ../..
}

# Verify Minecraft server is running
# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -s|--skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        -v|--minecraft-version)
            MINECRAFT_VERSION="$2"
            shift 2
            ;;
        -m|--mode)
            MINECRAFT_MODE="$2"
            shift 2
            ;;
        -d|--difficulty)
            MINECRAFT_DIFFICULTY="$2"
            shift 2
            ;;
        -b|--no-bedrock)
            USE_BEDROCK=false
            shift
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
            ;;
        --no-rollback)
            ROLLBACK_ENABLED=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            ;;
    esac
done

function verify_minecraft {
    echo -e "${BLUE}Verifying Minecraft server deployment...${NC}"
    
    # Get manager node IP
    MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
    MANAGER_KEY=$(realpath "ssh_keys/instance1.pem")
    
    if [[ -z "$MANAGER_IP" ]]; then
        echo -e "${RED}Could not determine manager node IP.${NC}"
        handle_error "Manager IP resolution failed" "verification"
    fi
    
    echo -e "${YELLOW}Checking Docker Swarm status...${NC}"
    ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "docker node ls" || handle_error "Docker Swarm status check failed" "verification"
    
    echo -e "${YELLOW}Checking Minecraft services status...${NC}"
    ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "docker service ls" || handle_error "Docker services status check failed" "verification"
    
    # Check if Minecraft server is responding
    echo -e "${YELLOW}Checking Minecraft Java server connectivity...${NC}"
    # We use a simple connection test - this doesn't validate the entire server is working
    # but checks if the port is open and accepting connections
    if ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "nc -z localhost 25565"; then
        echo -e "${GREEN}Minecraft Java server is accepting connections!${NC}"
    else
        echo -e "${YELLOW}Warning: Minecraft Java server port is not responding yet.${NC}"
        echo -e "${YELLOW}This might be because the server is still starting up. Check again in a few minutes.${NC}"
    fi
    
    # Check Bedrock if enabled
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "${YELLOW}Checking Minecraft Bedrock server connectivity...${NC}"
        if ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "nc -zu localhost 19132"; then
            echo -e "${GREEN}Minecraft Bedrock server is accepting connections!${NC}"
        else
            echo -e "${YELLOW}Warning: Minecraft Bedrock server port is not responding yet.${NC}"
            echo -e "${YELLOW}This might be because the server is still starting up. Check again in a few minutes.${NC}"
        fi
    fi
    
    # Display server information
    echo -e "${BLUE}Minecraft Server Information:${NC}"
    echo -e "${GREEN}Server IP Address: ${MANAGER_IP}${NC}"
    echo -e "${GREEN}Java Edition Port: 25565${NC}"
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "${GREEN}Bedrock Edition Port: 19132${NC}"
    fi
    echo -e "${GREEN}Game Mode: ${MINECRAFT_MODE}${NC}"
    echo -e "${GREEN}Difficulty: ${MINECRAFT_DIFFICULTY}${NC}"
    echo -e "${GREEN}Version: ${MINECRAFT_VERSION}${NC}"
    
    echo -e "${YELLOW}To connect to the server:${NC}"
    echo -e "  Java Edition: Use Minecraft Java client and connect to ${MANAGER_IP}:25565"
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "  Bedrock Edition: Use Minecraft Bedrock client and add server with address ${MANAGER_IP} and port 19132"
    fi
    
    echo -e "${YELLOW}To view server logs:${NC}"
    echo -e "  ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP \"docker service logs Mineclifford_minecraft-java\""
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "  ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP \"docker service logs Mineclifford_minecraft-bedrock\""
    fi
}

# Validate parameters
if [[ ! "$MINECRAFT_MODE" =~ ^(survival|creative|adventure|spectator)$ ]]; then
    echo -e "${RED}Error: Invalid game mode. Must be one of: survival, creative, adventure, spectator${NC}"
    exit 1
fi

if [[ ! "$MINECRAFT_DIFFICULTY" =~ ^(peaceful|easy|normal|hard)$ ]]; then
    echo -e "${RED}Error: Invalid difficulty. Must be one of: peaceful, easy, normal, hard${NC}"
    exit 1
fi

if [[ ! "$PROVIDER" =~ ^(aws|azure)$ ]]; then
    echo -e "${RED}Error: Invalid provider. Must be 'aws' or 'azure'${NC}"
    exit 1
fi

# Main execution flow
echo -e "${BLUE}Starting Mineclifford deployment with the following configuration:${NC}"
echo -e "Provider: ${YELLOW}$PROVIDER${NC}"
echo -e "Minecraft Version: ${YELLOW}$MINECRAFT_VERSION${NC}"
echo -e "Game Mode: ${YELLOW}$MINECRAFT_MODE${NC}"
echo -e "Difficulty: ${YELLOW}$MINECRAFT_DIFFICULTY${NC}"
echo -e "Bedrock Edition: ${YELLOW}$([[ "$USE_BEDROCK" == "true" ]] && echo "Enabled" || echo "Disabled")${NC}"

if [[ "$INTERACTIVE" == "true" ]]; then
    echo -e "${YELLOW}Continue with deployment? (y/n)${NC}"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment aborted.${NC}"
        exit 0
    fi
fi

validate_environment

if [[ "$SKIP_TERRAFORM" != "true" ]]; then
    run_terraform
else
    echo -e "${YELLOW}Skipping Terraform provisioning as requested.${NC}"
fi

run_ansible

verify_minecraft

# Save successful deployment marker
echo "$(date) - Minecraft $MINECRAFT_VERSION - $MINECRAFT_MODE mode - $MINECRAFT_DIFFICULTY difficulty" > .minecraft_deployment

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Minecraft deployment completed successfully!${NC}"
echo -e "${GREEN}Provider: $PROVIDER${NC}"
echo -e "${GREEN}Version: $MINECRAFT_VERSION${NC}"
echo -e "${GREEN}Mode: $MINECRAFT_MODE${NC}"
echo -e "${GREEN}Difficulty: $MINECRAFT_DIFFICULTY${NC}"
echo -e "${GREEN}Log file: $DEPLOYMENT_LOG${NC}"
echo -e "${GREEN}==========================================${NC}"

exit 0