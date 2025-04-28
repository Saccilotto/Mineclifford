#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTION="deploy"                # deploy, destroy, status
PROVIDER="aws"                 # aws, azure
ORCHESTRATION="swarm"          # swarm, kubernetes, local
SKIP_TERRAFORM=false
INTERACTIVE=true
DEPLOYMENT_LOG="minecraft_ops_$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_ENABLED=true
MINECRAFT_VERSION="latest"
MINECRAFT_MODE="survival"
MINECRAFT_DIFFICULTY="normal"
USE_BEDROCK=true
NAMESPACE="mineclifford"
KUBERNETES_PROVIDER="eks"      # eks, aks
MEMORY="2G"
FORCE_CLEANUP=false
SAVE_STATE=true
STORAGE_TYPE="s3"              # s3, azure, github

# Create log file
touch $DEPLOYMENT_LOG
exec > >(tee -a $DEPLOYMENT_LOG)
exec 2>&1

# Export environment variables for Ansible and Python
export ANSIBLE_FORCE_COLOR=true
export PYTHONIOENCODING=utf-8
export ANSIBLE_HOST_KEY_CHECKING=False

# Load environment variables from .env if it exists
if [[ -f ".env" ]]; then
    echo -e "${YELLOW}Loading environment variables from .env file...${NC}"
    set -o allexport
    source .env
    set +o allexport
    
    # Export Terraform-specific variables
    if [[ "$PROVIDER" == "azure" ]]; then
        export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    fi
else
    echo -e "${YELLOW}No .env file found. Using default values.${NC}"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "==========================================="
echo "Mineclifford Operations - $(date)"
echo "==========================================="

# Function to show help
function show_help {
    echo -e "${BLUE}Usage: $0 [ACTION] [OPTIONS]${NC}"
    echo -e "${YELLOW}Actions:${NC}"
    echo -e "  deploy                          Deploy Minecraft infrastructure (default)"
    echo -e "  destroy                         Destroy Minecraft infrastructure"
    echo -e "  status                          Check status of deployed infrastructure"
    echo -e "  save-state                      Save Terraform state"
    echo -e "  load-state                      Load Terraform state"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -p, --provider <aws|azure>      Specify the cloud provider (default: aws)"
    echo -e "  -o, --orchestration <swarm|kubernetes|local>"
    echo -e "                                  Orchestration method (default: swarm)"
    echo -e "  -s, --skip-terraform            Skip Terraform provisioning"
    echo -e "  -v, --minecraft-version VERSION Specify Minecraft version (default: latest)"
    echo -e "  -m, --mode <survival|creative>  Game mode (default: survival)"
    echo -e "  -d, --difficulty <peaceful|easy|normal|hard>"
    echo -e "                                  Game difficulty (default: normal)"
    echo -e "  -b, --no-bedrock                Skip Bedrock Edition deployment"
    echo -e "  -k, --k8s <eks|aks>             Kubernetes provider (default: eks)" 
    echo -e "  -n, --namespace NAMESPACE       Kubernetes namespace (default: mineclifford)"
    echo -e "  -mem, --memory MEMORY           Memory allocation for Java Edition (default: 2G)"
    echo -e "  -f, --force                     Force cleanup during destroy"
    echo -e "  --no-interactive                Run in non-interactive mode"
    echo -e "  --no-rollback                   Disable rollback on failure"
    echo -e "  --no-save-state                 Don't save Terraform state"
    echo -e "  --storage-type <s3|azure|github> State storage type (default: s3)"
    echo -e "  -h, --help                      Show this help message"
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 deploy --provider aws --orchestration swarm"
    echo -e "  $0 deploy --provider azure --orchestration kubernetes --k8s aks"
    echo -e "  $0 destroy --provider aws --orchestration swarm --force"
    echo -e "  $0 deploy --orchestration local --minecraft-version 1.19"
    exit 0
}

# Function for error handling
function handle_error {
    local exit_code=$?
    local error_message=$1
    local step=$2
    
    echo -e "${RED}ERROR: $error_message (Exit Code: $exit_code)${NC}" 
    echo -e "${RED}Operation failed during step: $step${NC}"
    
    if [[ "$ROLLBACK_ENABLED" == "true" && "$step" != "pre-operation" ]]; then
        echo -e "${YELLOW}Initiating rollback procedure...${NC}"
        
        case "$step" in
            "terraform")
                echo -e "${YELLOW}Rolling back infrastructure changes...${NC}"
                if [[ "$PROVIDER" == "aws" ]]; then
                    cd terraform/aws || exit 1
                    if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
                        cd kubernetes || exit 1
                    fi
                elif [[ "$PROVIDER" == "azure" ]]; then
                    cd terraform/azure || exit 1
                    if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
                        cd kubernetes || exit 1
                    fi
                fi
                terraform destroy -auto-approve
                cd - > /dev/null
                ;;
            "ansible"|"swarm")
                if [[ -f "static_ip.ini" ]]; then
                    echo -e "${YELLOW}Attempting to remove Docker stack...${NC}"
                    # Get manager node from inventory
                    MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
                    if [[ -n "$MANAGER_IP" ]]; then
                        echo -e "${YELLOW}Connecting to manager node $MANAGER_IP...${NC}"
                        ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker stack rm Mineclifford" || true
                    fi
                fi
                ;;
            "kubernetes")
                if [[ -n "$NAMESPACE" ]]; then
                    echo -e "${YELLOW}Removing Kubernetes deployments from namespace $NAMESPACE...${NC}"
                    kubectl delete namespace $NAMESPACE || true
                fi
                ;;
        esac
    fi
    
    echo -e "${YELLOW}See log file for details: $DEPLOYMENT_LOG${NC}"
    exit 1
}

# Pre-operation validation
function validate_environment {
    echo -e "${BLUE}Validating environment...${NC}"
    
    # Check required tools for all operations
    for cmd in terraform jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: Required tool '$cmd' is not installed.${NC}"
            handle_error "Missing required tool: $cmd" "pre-operation"
        fi
    done
    
    # Check orchestration-specific tools
    if [[ "$ORCHESTRATION" == "swarm" ]]; then
        if ! command -v ansible-playbook &> /dev/null; then
            echo -e "${RED}Error: Required tool 'ansible-playbook' is not installed.${NC}"
            handle_error "Missing required tool: ansible-playbook" "pre-operation"
        fi
    elif [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        if ! command -v kubectl &> /dev/null; then
            echo -e "${RED}Error: Required tool 'kubectl' is not installed.${NC}"
            handle_error "Missing required tool: kubectl" "pre-operation"
        fi
    elif [[ "$ORCHESTRATION" == "local" ]]; then
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Error: Required tool 'docker' is not installed.${NC}"
            handle_error "Missing required tool: docker" "pre-operation"
        fi
        if ! command -v docker-compose &> /dev/null; then
            echo -e "${RED}Error: Required tool 'docker-compose' is not installed.${NC}"
            handle_error "Missing required tool: docker-compose" "pre-operation"
        fi
    fi
    
    # Check provider-specific tools
    if [[ "$PROVIDER" == "aws" ]]; then
        if ! command -v aws &> /dev/null; then
            echo -e "${RED}Error: AWS CLI is not installed.${NC}"
            handle_error "Missing required tool: aws" "pre-operation"
        fi
        
        echo -e "${YELLOW}Validating AWS credentials...${NC}"
        if ! aws sts get-caller-identity &> /dev/null; then
            handle_error "Invalid AWS credentials" "pre-operation"
        fi
        
        if [[ "$ORCHESTRATION" == "kubernetes" && "$KUBERNETES_PROVIDER" == "eks" ]]; then
            if ! command -v eksctl &> /dev/null; then
                echo -e "${RED}Error: eksctl is not installed.${NC}"
                handle_error "Missing required tool: eksctl" "pre-operation"
            fi
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        if ! command -v az &> /dev/null; then
            echo -e "${RED}Error: Azure CLI is not installed.${NC}"
            handle_error "Missing required tool: az" "pre-operation"
        fi
        
        echo -e "${YELLOW}Validating Azure credentials...${NC}"
        if ! az account show &> /dev/null; then
            handle_error "Invalid Azure credentials" "pre-operation"
        fi
    fi

    # Validate parameters
    if [[ "$ACTION" == "deploy" ]]; then
        if [[ ! "$MINECRAFT_MODE" =~ ^(survival|creative|adventure|spectator)$ ]]; then
            echo -e "${RED}Error: Invalid game mode. Must be one of: survival, creative, adventure, spectator${NC}"
            exit 1
        fi

        if [[ ! "$MINECRAFT_DIFFICULTY" =~ ^(peaceful|easy|normal|hard)$ ]]; then
            echo -e "${RED}Error: Invalid difficulty. Must be one of: peaceful, easy, normal, hard${NC}"
            exit 1
        fi
    fi

    if [[ ! "$PROVIDER" =~ ^(aws|azure)$ ]]; then
        echo -e "${RED}Error: Invalid provider. Must be 'aws' or 'azure'${NC}"
        exit 1
    fi

    if [[ ! "$ORCHESTRATION" =~ ^(swarm|kubernetes|local)$ ]]; then
        echo -e "${RED}Error: Invalid orchestration. Must be 'swarm', 'kubernetes', or 'local'${NC}"
        exit 1
    fi

    if [[ "$ORCHESTRATION" == "kubernetes" && ! "$KUBERNETES_PROVIDER" =~ ^(eks|aks)$ ]]; then
        echo -e "${RED}Error: Invalid Kubernetes provider. Must be 'eks' or 'aks'${NC}"
        exit 1
    fi

    echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Minecraft deployment completed successfully!${NC}"
echo -e "${GREEN}Provider: $PROVIDER${NC}"
if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
    echo -e "${GREEN}Kubernetes Provider: $KUBERNETES_PROVIDER${NC}"
fi
echo -e "${GREEN}Orchestration: $ORCHESTRATION${NC}"
echo -e "${GREEN}Version: $MINECRAFT_VERSION${NC}"
echo -e "${GREEN}Mode: $MINECRAFT_MODE${NC}"
echo -e "${GREEN}Difficulty: $MINECRAFT_DIFFICULTY${NC}"
echo -e "${GREEN}Log file: $DEPLOYMENT_LOG${NC}"
echo -e "${GREEN}==========================================${NC}"
}

# Parse command line arguments
# First parameter is the action
if [[ $# -gt 0 && "$1" =~ ^(deploy|destroy|status|save-state|load-state)$ ]]; then
    ACTION="$1"
    shift
fi

# Parse remaining parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -o|--orchestration)
            ORCHESTRATION="$2"
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
        -k|--k8s)
            KUBERNETES_PROVIDER="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -mem|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_CLEANUP=true
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
        --no-save-state)
            SAVE_STATE=false
            shift
            ;;
        --storage-type)
            STORAGE_TYPE="$2"
            shift 2
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

# Validate environment
validate_environment

# Execute action
case "$ACTION" in
    deploy)
        deploy_infrastructure
        ;;
    destroy)
        if [[ "$INTERACTIVE" == "true" && "$FORCE_CLEANUP" != "true" ]]; then
            echo -e "${RED}WARNING: This will destroy all resources. There is NO UNDO.${NC}"
            echo -e "${YELLOW}Do you really want to destroy all resources? Type 'yes' to confirm.${NC}"
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                echo -e "${YELLOW}Destruction aborted.${NC}"
                exit 0
            fi
        fi
        destroy_infrastructure
        ;;
    status)
        check_status
        ;;
    save-state)
        save_terraform_state
        ;;
    load-state)
        load_terraform_state
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        show_help
        ;;
esac

exit 0}Environment validation passed.${NC}"
}

# Function to save Terraform state
function save_terraform_state {
    if [[ "$SAVE_STATE" != "true" ]]; then
        echo -e "${YELLOW}Skipping state saving as requested.${NC}"
        return
    fi
    
    echo -e "${BLUE}Saving Terraform state...${NC}"
    
    local tf_dir=""
    if [[ "$PROVIDER" == "aws" ]]; then
        tf_dir="terraform/aws"
        if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            tf_dir="${tf_dir}/kubernetes"
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        tf_dir="terraform/azure"
        if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            tf_dir="${tf_dir}/kubernetes"
        fi
    fi
    
    ./save-terraform-state.sh --provider "$PROVIDER" --action save --storage "$STORAGE_TYPE"
    
    echo -e "${GREEN}Terraform state saved successfully.${NC}"
}

# Function to load Terraform state
function load_terraform_state {
    echo -e "${BLUE}Loading Terraform state...${NC}"
    
    ./save-terraform-state.sh --provider "$PROVIDER" --action load --storage "$STORAGE_TYPE"
    
    echo -e "${GREEN}Terraform state loaded successfully.${NC}"
}

# Run Terraform with error handling
function run_terraform {
    if [[ "$SKIP_TERRAFORM" == "true" ]]; then
        echo -e "${YELLOW}Skipping Terraform provisioning as requested.${NC}"
        return
    fi
    
    echo -e "${BLUE}Running Terraform for $PROVIDER...${NC}"
    
    # Determine the directory
    local tf_dir=""
    if [[ "$PROVIDER" == "aws" ]]; then
        tf_dir="terraform/aws"
        if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            tf_dir="${tf_dir}/kubernetes"
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        tf_dir="terraform/azure"
        if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            tf_dir="${tf_dir}/kubernetes"
        fi
    fi
    
    # Check if directory exists
    if [[ ! -d "$tf_dir" ]]; then
        handle_error "Terraform directory $tf_dir does not exist" "terraform"
    fi
    
    cd "$tf_dir" || handle_error "Failed to change to directory $tf_dir" "terraform"
    
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init || handle_error "Terraform initialization failed" "terraform"
    
    echo -e "${YELLOW}Planning Terraform changes...${NC}"
    terraform plan -out=tf.plan || handle_error "Terraform plan failed" "terraform"
    
    echo -e "${YELLOW}Applying Terraform changes...${NC}"
    terraform apply tf.plan || handle_error "Terraform apply failed" "terraform"
    
    cd - > /dev/null
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
minecraft_java_memory: "$MEMORY"
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
    cd deployment/ansible || handle_error "Failed to change to ansible directory" "ansible"
    
    # Test connectivity
    echo -e "${YELLOW}Testing connectivity to hosts...${NC}"
    ansible -i ../../static_ip.ini all -m ping || handle_error "Ansible connectivity test failed" "ansible"
    
    # Run main playbook
    echo -e "${YELLOW}Running Minecraft setup playbook...${NC}"
    if [[ "$ORCHESTRATION" == "swarm" ]]; then
        ansible-playbook -i ../../static_ip.ini swarm_setup.yml -e "@minecraft_vars.yml" || handle_error "Ansible playbook execution failed" "ansible"
    else
        ansible-playbook -i ../../static_ip.ini minecraft_setup.yml -e "@minecraft_vars.yml" || handle_error "Ansible playbook execution failed" "ansible"
    fi
    
    cd ../..
}

# Deploy to Kubernetes
function deploy_to_kubernetes {
    echo -e "${BLUE}Deploying Minecraft to Kubernetes...${NC}"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        kubectl create namespace $NAMESPACE || handle_error "Failed to create namespace" "kubernetes"
    fi
    
    # Update deployment files with configuration
    echo -e "${YELLOW}Configuring Minecraft deployment files...${NC}"
    
    # Update minecraft-java-deployment.yaml
    sed -i "s|image: itzg/minecraft-server:latest|image: itzg/minecraft-server:$MINECRAFT_VERSION|g" deployment/kubernetes/minecraft-java-deployment.yaml
    sed -i "s|value: \"survival\"|value: \"$MINECRAFT_MODE\"|g" deployment/kubernetes/minecraft-java-deployment.yaml
    sed -i "s|value: \"normal\"|value: \"$MINECRAFT_DIFFICULTY\"|g" deployment/kubernetes/minecraft-java-deployment.yaml
    sed -i "s|memory: \"2Gi\"|memory: \"$MEMORY\"|g" deployment/kubernetes/minecraft-java-deployment.yaml
    
    # Update minecraft-bedrock-deployment.yaml if using Bedrock
    if [[ "$USE_BEDROCK" == "true" ]]; then
        sed -i "s|image: itzg/minecraft-bedrock-server:latest|image: itzg/minecraft-bedrock-server:$MINECRAFT_VERSION|g" deployment/kubernetes/minecraft-bedrock-deployment.yaml
        sed -i "s|value: \"survival\"|value: \"$MINECRAFT_MODE\"|g" deployment/kubernetes/minecraft-bedrock-deployment.yaml
        sed -i "s|value: \"normal\"|value: \"$MINECRAFT_DIFFICULTY\"|g" deployment/kubernetes/minecraft-bedrock-deployment.yaml
    fi
    
    # Apply Kubernetes deployments
    echo -e "${YELLOW}Applying Kubernetes deployments...${NC}"
    
    kubectl apply -f deployment/kubernetes/minecraft-java-deployment.yaml --namespace=$NAMESPACE || handle_error "Failed to deploy Minecraft Java" "kubernetes"
    
    if [[ "$USE_BEDROCK" == "true" ]]; then
        kubectl apply -f deployment/kubernetes/minecraft-bedrock-deployment.yaml --namespace=$NAMESPACE || handle_error "Failed to deploy Minecraft Bedrock" "kubernetes"
    fi
    
    kubectl apply -f deployment/kubernetes/monitoring.yaml --namespace=$NAMESPACE || handle_error "Failed to deploy monitoring" "kubernetes"
    kubectl apply -f deployment/kubernetes/ingress.yaml --namespace=$NAMESPACE || handle_error "Failed to deploy ingress" "kubernetes"
    
    echo -e "${GREEN}Minecraft deployed to Kubernetes successfully.${NC}"
}

# Deploy local Docker
function deploy_local {
    echo -e "${BLUE}Deploying Minecraft locally with Docker...${NC}"
    
    # Create necessary directories
    mkdir -p data/minecraft-java
    mkdir -p data/minecraft-bedrock
    mkdir -p data/rcon
    
    # Create a docker-compose file with our parameters
    echo -e "${YELLOW}Creating docker-compose.yml with:${NC}"
    echo -e "  Version: ${YELLOW}$MINECRAFT_VERSION${NC}"
    echo -e "  Game Mode: ${YELLOW}$MINECRAFT_MODE${NC}"
    echo -e "  Difficulty: ${YELLOW}$MINECRAFT_DIFFICULTY${NC}"
    echo -e "  Memory: ${YELLOW}$MEMORY${NC}"
    echo -e "  Bedrock Edition: ${YELLOW}$([[ "$USE_BEDROCK" == "true" ]] && echo "Enabled" || echo "Disabled")${NC}"
    
    # Create the docker-compose.yml file
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  # Java Edition Minecraft Server
  minecraft-java:
    image: itzg/minecraft-server:$MINECRAFT_VERSION
    container_name: minecraft-java
    environment:
      - EULA=TRUE
      - TYPE=PAPER
      - MEMORY=$MEMORY
      - DIFFICULTY=$MINECRAFT_DIFFICULTY
      - MODE=$MINECRAFT_MODE
      - MOTD=Mineclifford Java Server
      - ALLOW_NETHER=true
      - ENABLE_COMMAND_BLOCK=true
      - SPAWN_PROTECTION=0
      - VIEW_DISTANCE=10
      - TZ=America/Sao_Paulo
    ports:
      - "25565:25565"
    volumes:
      - ./data/minecraft-java:/data
    restart: unless-stopped
EOF
    
    # Add Bedrock if enabled
    if [[ "$USE_BEDROCK" == "true" ]]; then
      cat >> docker-compose.yml << EOF

  # Bedrock Edition Minecraft Server
  minecraft-bedrock:
    image: itzg/minecraft-bedrock-server:$MINECRAFT_VERSION
    container_name: minecraft-bedrock
    environment:
      - EULA=TRUE
      - GAMEMODE=$MINECRAFT_MODE
      - DIFFICULTY=$MINECRAFT_DIFFICULTY
      - SERVER_NAME=Mineclifford Bedrock Server
      - LEVEL_NAME=Mineclifford
      - ALLOW_CHEATS=false
      - TZ=America/Sao_Paulo
    ports:
      - "19132:19132/udp"
    volumes:
      - ./data/minecraft-bedrock:/data
    restart: unless-stopped
EOF
    fi
    
    # Add RCON
    cat >> docker-compose.yml << EOF

  # RCON Web Admin
  rcon-web-admin:
    image: itzg/rcon:latest
    container_name: rcon-web-admin
    ports:
      - "4326:4326"
      - "4327:4327"
    volumes:
      - ./data/rcon:/opt/rcon-web-admin/db
    environment:
      - RWA_PASSWORD=minecraft
      - RWA_ADMIN=true
    depends_on:
      - minecraft-java
    restart: unless-stopped
EOF
    
    # Start the services
    echo -e "${YELLOW}Starting Minecraft servers...${NC}"
    docker-compose up -d || handle_error "Failed to start Docker containers" "local"
    
    # Check status
    echo -e "${YELLOW}Checking if services are running...${NC}"
    sleep 10
    docker-compose ps || handle_error "Failed to check Docker container status" "local"
}

# Check deployed infrastructure status
function check_status {
    echo -e "${BLUE}Checking deployment status...${NC}"
    
    if [[ "$ORCHESTRATION" == "local" ]]; then
        # Check local Docker containers
        if command -v docker &> /dev/null; then
            echo -e "${YELLOW}Checking Docker containers:${NC}"
            docker ps --filter "name=minecraft" || handle_error "Failed to check Docker containers" "status"
        else
            handle_error "Docker is not installed" "status"
        fi
        
    elif [[ "$ORCHESTRATION" == "swarm" ]]; then
        # Check Docker Swarm services
        if [[ -f "static_ip.ini" ]]; then
            MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
            
            if [[ -n "$MANAGER_IP" ]]; then
                echo -e "${YELLOW}Checking Docker Swarm services on $MANAGER_IP:${NC}"
                ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker service ls" || handle_error "Failed to check Docker Swarm services" "status"
            else
                handle_error "Could not find manager IP in inventory" "status"
            fi
        else
            handle_error "Inventory file static_ip.ini not found" "status"
        fi
        
    elif [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        # Check Kubernetes deployments
        if command -v kubectl &> /dev/null; then
            echo -e "${YELLOW}Checking Kubernetes deployments in namespace $NAMESPACE:${NC}"
            kubectl get deployments --namespace=$NAMESPACE || handle_error "Failed to check Kubernetes deployments" "status"
            
            echo -e "${YELLOW}Checking Kubernetes services in namespace $NAMESPACE:${NC}"
            kubectl get services --namespace=$NAMESPACE || handle_error "Failed to check Kubernetes services" "status"
            
            echo -e "${YELLOW}Checking Kubernetes pods in namespace $NAMESPACE:${NC}"
            kubectl get pods --namespace=$NAMESPACE || handle_error "Failed to check Kubernetes pods" "status"
        else
            handle_error "kubectl is not installed" "status"
        fi
    fi
    
    echo -e "${GREEN}Status check completed.${NC}"
}

# Destroy infrastructure
function destroy_infrastructure {
    echo -e "${BLUE}Destroying Minecraft infrastructure...${NC}"
    
    if [[ "$ORCHESTRATION" == "local" ]]; then
        # Destroy local Docker containers
        echo -e "${YELLOW}Stopping and removing Docker containers...${NC}"
        docker-compose down -v || handle_error "Failed to stop Docker containers" "destroy"
        
    elif [[ "$ORCHESTRATION" == "swarm" || "$ORCHESTRATION" == "kubernetes" ]]; then
        # Run the destroy.sh script
        local destroy_opts="--provider $PROVIDER"
        
        if [[ "$FORCE_CLEANUP" == "true" ]]; then
            destroy_opts="$destroy_opts --yes"
        fi
        
        echo -e "${YELLOW}Running destroy script with options: $destroy_opts${NC}"
        ./destroy.sh $destroy_opts || handle_error "Failed to destroy infrastructure" "destroy"
        
        # Verify destruction
        echo -e "${YELLOW}Verifying destruction...${NC}"
        ./verify-destruction.sh --provider $PROVIDER ${FORCE_CLEANUP:+--force} || handle_error "Failed to verify destruction" "destroy"
    fi
    
    echo -e "${GREEN}Infrastructure destroyed successfully.${NC}"
}

# Deploy Minecraft infrastructure
function deploy_infrastructure {
    echo -e "${BLUE}Starting Minecraft deployment with the following configuration:${NC}"
    echo -e "Provider: ${YELLOW}$PROVIDER${NC}"
    echo -e "Orchestration: ${YELLOW}$ORCHESTRATION${NC}"
    if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        echo -e "Kubernetes Provider: ${YELLOW}$KUBERNETES_PROVIDER${NC}"
        echo -e "Kubernetes Namespace: ${YELLOW}$NAMESPACE${NC}"
    fi
    echo -e "Minecraft Version: ${YELLOW}$MINECRAFT_VERSION${NC}"
    echo -e "Game Mode: ${YELLOW}$MINECRAFT_MODE${NC}"
    echo -e "Difficulty: ${YELLOW}$MINECRAFT_DIFFICULTY${NC}"
    echo -e "Memory: ${YELLOW}$MEMORY${NC}"
    echo -e "Bedrock Edition: ${YELLOW}$([[ "$USE_BEDROCK" == "true" ]] && echo "Enabled" || echo "Disabled")${NC}"
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo -e "${YELLOW}Continue with deployment? (y/n)${NC}"
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Deployment aborted.${NC}"
            exit 0
        fi
    fi
    
    # Execute deployment based on orchestration type
    if [[ "$ORCHESTRATION" == "local" ]]; then
        deploy_local
    else
        # For both swarm and kubernetes, we need to run Terraform first
        run_terraform
        
        if [[ "$ORCHESTRATION" == "swarm" ]]; then
            run_ansible
        elif [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            deploy_to_kubernetes
        fi
    fi
    
    # Save state if enabled
    if [[ "$SAVE_STATE" == "true" ]]; then
        save_terraform_state
    fi
    
    # Display completion message
    local success_marker_file=""
    if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        success_marker_file=".minecraft_k8s_deployment"
    else
        success_marker_file=".minecraft_deployment"
    fi
    
    # Save successful deployment marker
    echo "$(date) - Minecraft $MINECRAFT_VERSION - $MINECRAFT_MODE mode - $MINECRAFT_DIFFICULTY difficulty" > $success_marker_file
    
    echo -e "${GREEN