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
SERVER_NAMES=("instance1")     # Default server names

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
    echo -e "  backup                          Backup Minecraft worlds"
    echo -e "  restore                         Restore Minecraft worlds from backup"
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
    echo -e "  -sn, --server-names NAMES       Comma-separated list of server names (default: instance1)"
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
    echo -e "  $0 backup --provider aws --orchestration swarm"
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
            "local")
                echo -e "${YELLOW}Stopping and removing local Docker containers...${NC}"
                docker-compose down -v || true
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
            handle_error "Invalid game mode. Must be one of: survival, creative, adventure, spectator" "pre-operation"
        fi

        if [[ ! "$MINECRAFT_DIFFICULTY" =~ ^(peaceful|easy|normal|hard)$ ]]; then
            handle_error "Invalid difficulty. Must be one of: peaceful, easy, normal, hard" "pre-operation"
        fi
    fi

    if [[ ! "$PROVIDER" =~ ^(aws|azure)$ ]]; then
        handle_error "Invalid provider. Must be 'aws' or 'azure'" "pre-operation"
    fi

    if [[ ! "$ORCHESTRATION" =~ ^(swarm|kubernetes|local)$ ]]; then
        handle_error "Invalid orchestration. Must be 'swarm', 'kubernetes', or 'local'" "pre-operation"
    fi

    if [[ "$ORCHESTRATION" == "kubernetes" && ! "$KUBERNETES_PROVIDER" =~ ^(eks|aks)$ ]]; then
        handle_error "Invalid Kubernetes provider. Must be 'eks' or 'aks'" "pre-operation"
    fi

    echo -e "${GREEN}Environment validation passed.${NC}"
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
    
    # Create terraform.tfvars file with our variables
    cat > "$tf_dir/terraform.tfvars" << EOF
    # Generated by minecraft-ops.sh at $(date)
    vm_names = [${SERVER_NAMES[@]/#/\"}${SERVER_NAMES[@]/%/\"}]
    project_name = "mineclifford"
    resource_group_name = "mineclifford"
    EOF

    # Add provider-specific variables
    if [[ "$PROVIDER" == "azure" ]]; then
        echo "azure_subscription_id = \"$AZURE_SUBSCRIPTION_ID\"" >> "$tf_dir/terraform.tfvars"
    fi
    
    cd "$tf_dir" || handle_error "Failed to change to directory $tf_dir" "terraform"
    
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init || handle_error "Terraform initialization failed" "terraform"
    
    echo -e "${YELLOW}Planning Terraform changes...${NC}"
    terraform plan -out=tf.plan || handle_error "Terraform plan failed" "terraform"
    
    echo -e "${YELLOW}Applying Terraform changes...${NC}"
    terraform apply tf.plan || handle_error "Terraform apply failed" "terraform"
    
    # Extract outputs for reference
    echo -e "${YELLOW}Extracting Terraform outputs...${NC}"
    
    if [[ "$PROVIDER" == "aws" ]]; then
        # Save instance public IPs to a file
        terraform output -json instance_public_ips > ../../../instance_ips.json
    elif [[ "$PROVIDER" == "azure" ]]; then
        # Save VM public IPs to a file
        terraform output -json vm_public_ips > ../../../instance_ips.json
    fi
    
    cd - > /dev/null
    echo -e "${GREEN}Terraform execution completed successfully.${NC}"
    
    echo -e "${YELLOW}Waiting for instances to initialize (60 seconds)...${NC}"
    for i in {1..60}; do
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

# Server Names
server_names:
$(for name in "${SERVER_NAMES[@]}"; do echo "  - $name"; done)
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
    
    # Final connectivity verification
    echo -e "${YELLOW}Verifying final deployment...${NC}"
    
    # Get manager node from inventory
    MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
    if [[ -n "$MANAGER_IP" ]]; then
        echo -e "${YELLOW}Checking services on manager node $MANAGER_IP...${NC}"
        ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker service ls" || echo -e "${YELLOW}Unable to check services, may still be initializing...${NC}"
    fi
    
    echo -e "${GREEN}Ansible deployment completed successfully.${NC}"
}

# Deploy to Kubernetes
function deploy_to_kubernetes {
    echo -e "${BLUE}Deploying Minecraft to Kubernetes...${NC}"
    
    # Setup kubectl context based on provider
    if [[ "$PROVIDER" == "aws" ]]; then
        echo -e "${YELLOW}Configuring kubectl for EKS...${NC}"
        # Get the cluster name from Terraform output
        CLUSTER_NAME=$(cd terraform/aws/kubernetes && terraform output -raw cluster_name)
        aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION || handle_error "Failed to configure kubectl for EKS" "kubernetes"
    elif [[ "$PROVIDER" == "azure" ]]; then
        echo -e "${YELLOW}Configuring kubectl for AKS...${NC}"
        # Get the resource group and cluster name from Terraform output
        RG_NAME=$(cd terraform/azure/kubernetes && terraform output -raw kubernetes_cluster_resource_group)
        CLUSTER_NAME=$(cd terraform/azure/kubernetes && terraform output -raw kubernetes_cluster_name)
        az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME || handle_error "Failed to configure kubectl for AKS" "kubernetes"
    fi
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        kubectl create namespace $NAMESPACE || handle_error "Failed to create namespace" "kubernetes"
    else
        # Check if we're redeploying to an existing namespace
        echo -e "${YELLOW}Namespace $NAMESPACE already exists. Checking for existing resources...${NC}"
        if kubectl get deployments -n $NAMESPACE 2>/dev/null | grep -q "minecraft"; then
            echo -e "${YELLOW}Found existing Minecraft deployments in namespace. They will be replaced.${NC}"
            if [[ "$INTERACTIVE" == "true" ]]; then
                echo -e "${YELLOW}Continue? (yes/no)${NC}"
                read -r confirm
                if [[ "$confirm" != "yes" ]]; then
                    handle_error "Deployment cancelled by user" "kubernetes"
                fi
            fi
        fi
    fi
    
    # Update deployment files with configuration
    echo -e "${YELLOW}Configuring Minecraft deployment files...${NC}"
    
    # Create configmap for settings
    kubectl create configmap minecraft-settings -n $NAMESPACE --from-literal=VERSION=$MINECRAFT_VERSION \
        --from-literal=GAMEMODE=$MINECRAFT_MODE \
        --from-literal=DIFFICULTY=$MINECRAFT_DIFFICULTY \
        --from-literal=MEMORY=$MEMORY \
        --from-literal=ALLOW_BEDROCK=$USE_BEDROCK \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Update deployments based on provider
    if [[ "$PROVIDER" == "aws" ]]; then
        echo -e "${YELLOW}Applying AWS-specific Kubernetes deployments...${NC}"
        kubectl apply -k deployment/kubernetes/aws/ -n $NAMESPACE || handle_error "Failed to apply AWS Kubernetes manifests" "kubernetes"
    elif [[ "$PROVIDER" == "azure" ]]; then
        echo -e "${YELLOW}Applying Azure-specific Kubernetes deployments...${NC}"
        kubectl apply -k deployment/kubernetes/azure/ -n $NAMESPACE || handle_error "Failed to apply Azure Kubernetes manifests" "kubernetes"
    else
        # Default to applying base configurations
        echo -e "${YELLOW}Applying base Kubernetes deployments...${NC}"
        kubectl apply -f deployment/kubernetes/base/minecraft-java-deployment.yaml -n $NAMESPACE || handle_error "Failed to deploy Minecraft Java" "kubernetes"
        
        if [[ "$USE_BEDROCK" == "true" ]]; then
            kubectl apply -f deployment/kubernetes/base/minecraft-bedrock-deployment.yaml -n $NAMESPACE || handle_error "Failed to deploy Minecraft Bedrock" "kubernetes"
        fi
        
        kubectl apply -f deployment/kubernetes/monitoring.yaml -n $NAMESPACE || handle_error "Failed to deploy monitoring" "kubernetes"
        kubectl apply -f deployment/kubernetes/ingress.yaml -n $NAMESPACE || handle_error "Failed to deploy ingress" "kubernetes"
    fi
    
    # Wait for deployments to be ready
    echo -e "${YELLOW}Waiting for deployments to be ready...${NC}"
    kubectl rollout status deployment/minecraft-java -n $NAMESPACE --timeout=300s || echo -e "${YELLOW}Minecraft Java deployment still in progress...${NC}"
    
    if [[ "$USE_BEDROCK" == "true" ]]; then
        kubectl rollout status deployment/minecraft-bedrock -n $NAMESPACE --timeout=300s || echo -e "${YELLOW}Minecraft Bedrock deployment still in progress...${NC}"
    fi
    
    # Get service information for connecting
    echo -e "${YELLOW}Getting service information...${NC}"
    kubectl get services -n $NAMESPACE
    
    echo -e "${GREEN}Minecraft deployed to Kubernetes successfully.${NC}"
}

# Deploy local Docker
function deploy_local {
    echo -e "${BLUE}Deploying Minecraft locally with Docker...${NC}"
    
    # Create necessary directories
    mkdir -p data/minecraft-java
    mkdir -p data/minecraft-bedrock
    mkdir -p data/rcon
    mkdir -p data/prometheus
    mkdir -p data/grafana
    
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
    networks:
      - minecraft_network
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
    networks:
      - minecraft_network
EOF
    fi
    
    # Add RCON and monitoring
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
    networks:
      - minecraft_network
      
  # Prometheus for monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./data/prometheus:/prometheus
      - ./deployment/swarm/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./deployment/swarm/prometheus/rules:/etc/prometheus/rules
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
    restart: unless-stopped
    networks:
      - minecraft_network
      
  # Grafana for visualization
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - ./data/grafana:/var/lib/grafana
      - ./deployment/swarm/grafana/dashboards:/etc/grafana/provisioning/dashboards
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    restart: unless-stopped
    networks:
      - minecraft_network
      
  # Minecraft exporter for Prometheus
  minecraft-exporter:
    image: hkubota/minecraft-exporter:latest
    container_name: minecraft-exporter
    ports:
      - "9150:9150"
    environment:
      - MC_SERVER=minecraft-java
      - MC_PORT=25565
    restart: unless-stopped
    networks:
      - minecraft_network

networks:
  minecraft_network:
    driver: bridge
EOF
    
    # Start the services
    echo -e "${YELLOW}Starting Minecraft servers...${NC}"
    docker-compose up -d || handle_error "Failed to start Docker containers" "local"
    
    # Check status
    echo -e "${YELLOW}Checking if services are running...${NC}"
    sleep 10
    docker-compose ps || handle_error "Failed to check Docker container status" "local"
    
    echo -e "${GREEN}Local deployment completed successfully.${NC}"
    echo -e "${YELLOW}Access Minecraft Java server at: localhost:25565${NC}"
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "${YELLOW}Access Minecraft Bedrock server at: localhost:19132${NC}"
    fi
    echo -e "${YELLOW}Access Grafana at: http://localhost:3000 (admin/admin)${NC}"
    echo -e "${YELLOW}Access Prometheus at: http://localhost:9090${NC}"
    echo -e "${YELLOW}Access RCON Web Admin at: http://localhost:4326 (admin/minecraft)${NC}"
}

# Backup Minecraft worlds
function backup_worlds {
    echo -e "${BLUE}Backing up Minecraft worlds...${NC}"
    
    # Create backup directory if it doesn't exist
    local BACKUP_DIR="minecraft-backups"
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    
if [[ "$ORCHESTRATION" == "local" ]]; then
        # Back up local volumes
        echo -e "${YELLOW}Backing up local Minecraft Java world...${NC}"
        tar -czf "$BACKUP_DIR/minecraft_java_$TIMESTAMP.tar.gz" -C data/minecraft-java .
        
        if [[ "$USE_BEDROCK" == "true" ]]; then
            echo -e "${YELLOW}Backing up local Minecraft Bedrock world...${NC}"
            tar -czf "$BACKUP_DIR/minecraft_bedrock_$TIMESTAMP.tar.gz" -C data/minecraft-bedrock .
        fi
        
    elif [[ "$ORCHESTRATION" == "swarm" ]]; then
        # Backup remote Docker Swarm volumes
        if [[ ! -f "static_ip.ini" ]]; then
            handle_error "Inventory file static_ip.ini not found" "backup"
        fi
        
        # Get manager node from inventory
        MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
        
        if [[ -n "$MANAGER_IP" ]]; then
            echo -e "${YELLOW}Connecting to manager node $MANAGER_IP for backup...${NC}"
            
            # Run backup command on remote server
            ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "bash /home/ubuntu/backup-minecraft.sh" || handle_error "Remote backup failed" "backup"
            
            # Create local backup directory
            mkdir -p "$BACKUP_DIR/$TIMESTAMP"
            
            # Copy backups from remote server
            echo -e "${YELLOW}Downloading backups from remote server...${NC}"
            scp $SSH_OPTS -i ssh_keys/instance1.pem "ubuntu@$MANAGER_IP:/home/ubuntu/minecraft-backups/*.tar.gz" "$BACKUP_DIR/$TIMESTAMP/" || handle_error "Failed to download backups" "backup"
        else
            handle_error "Could not find manager IP in inventory" "backup"
        fi
        
    elif [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        # Backup Kubernetes volumes
        echo -e "${YELLOW}Backing up Kubernetes volumes...${NC}"
        
        # Create backup script
        cat > /tmp/k8s-backup.sh << EOF
#!/bin/bash
# Get the Minecraft Java pod name
POD=\$(kubectl get pod -l app=minecraft-java -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}")
echo "Backing up from pod: \$POD"

# Create backup directory
mkdir -p /tmp/minecraft-backup
cd /tmp/minecraft-backup

# Backup Java world
kubectl exec -n $NAMESPACE \$POD -- tar -cz -C /data . > minecraft_java_$TIMESTAMP.tar.gz

# Backup Bedrock world if enabled
if kubectl get pod -l app=minecraft-bedrock -n $NAMESPACE &>/dev/null; then
    BEDROCK_POD=\$(kubectl get pod -l app=minecraft-bedrock -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}")
    kubectl exec -n $NAMESPACE \$BEDROCK_POD -- tar -cz -C /data . > minecraft_bedrock_$TIMESTAMP.tar.gz
fi
EOF
        
        # Make the script executable
        chmod +x /tmp/k8s-backup.sh
        
        # Run the backup script
        /tmp/k8s-backup.sh || handle_error "Kubernetes backup failed" "backup"
        
        # Copy backups to backup directory
        mkdir -p "$BACKUP_DIR/$TIMESTAMP"
        cp /tmp/minecraft-backup/*.tar.gz "$BACKUP_DIR/$TIMESTAMP/" || handle_error "Failed to save backups" "backup"
        
        # Clean up
        rm -rf /tmp/minecraft-backup
        rm /tmp/k8s-backup.sh
    fi
    
    echo -e "${GREEN}Backup completed successfully.${NC}"
    echo -e "${YELLOW}Backups saved to: $BACKUP_DIR${NC}"
    
    # Clean up old backups (keep last 5)
    echo -e "${YELLOW}Cleaning up old backups (keeping last 5)...${NC}"
    (cd "$BACKUP_DIR" && ls -t | grep -v "/$" | tail -n +6 | xargs -r rm -rf)
}

# Restore Minecraft worlds
function restore_worlds {
    echo -e "${BLUE}Restoring Minecraft worlds...${NC}"
    
    # List available backups
    local BACKUP_DIR="minecraft-backups"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        handle_error "Backup directory not found" "restore"
    fi
    
    # List backups in reverse order (newest first)
    echo -e "${YELLOW}Available backups:${NC}"
    local backup_list=($(ls -t "$BACKUP_DIR"))
    
    if [[ ${#backup_list[@]} -eq 0 ]]; then
        handle_error "No backups found" "restore"
    fi
    
    # Print the list with numbers
    for i in "${!backup_list[@]}"; do
        echo -e "$((i+1)). ${backup_list[$i]}"
    done
    
    # Prompt for backup selection unless in non-interactive mode
    local backup_selection=0
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo -e "${YELLOW}Enter backup number to restore (1-${#backup_list[@]}) or 'q' to quit:${NC}"
        read -r selection
        
        if [[ "$selection" == "q" ]]; then
            echo -e "${YELLOW}Restore cancelled.${NC}"
            exit 0
        fi
        
        backup_selection=$((selection-1))
    else
        # In non-interactive mode, use the latest backup
        backup_selection=0
    fi
    
    # Validate selection
    if [[ $backup_selection -lt 0 || $backup_selection -ge ${#backup_list[@]} ]]; then
        handle_error "Invalid backup selection" "restore"
    fi
    
    local selected_backup="${backup_list[$backup_selection]}"
    echo -e "${YELLOW}Selected backup: $selected_backup${NC}"
    
    # Restore based on orchestration method
    if [[ "$ORCHESTRATION" == "local" ]]; then
        # Restore local volumes
        if [[ -f "$BACKUP_DIR/$selected_backup/minecraft_java_$selected_backup.tar.gz" ]]; then
            echo -e "${YELLOW}Stopping Docker containers...${NC}"
            docker-compose down
            
            echo -e "${YELLOW}Restoring Minecraft Java world...${NC}"
            rm -rf data/minecraft-java/*
            tar -xzf "$BACKUP_DIR/$selected_backup/minecraft_java_$selected_backup.tar.gz" -C data/minecraft-java
            
            if [[ "$USE_BEDROCK" == "true" && -f "$BACKUP_DIR/$selected_backup/minecraft_bedrock_$selected_backup.tar.gz" ]]; then
                echo -e "${YELLOW}Restoring Minecraft Bedrock world...${NC}"
                rm -rf data/minecraft-bedrock/*
                tar -xzf "$BACKUP_DIR/$selected_backup/minecraft_bedrock_$selected_backup.tar.gz" -C data/minecraft-bedrock
            fi
            
            echo -e "${YELLOW}Starting Docker containers...${NC}"
            docker-compose up -d
        else
            # Older backup format
            if [[ -f "$BACKUP_DIR/minecraft_java_$selected_backup.tar.gz" ]]; then
                echo -e "${YELLOW}Stopping Docker containers...${NC}"
                docker-compose down
                
                echo -e "${YELLOW}Restoring Minecraft Java world...${NC}"
                rm -rf data/minecraft-java/*
                tar -xzf "$BACKUP_DIR/minecraft_java_$selected_backup.tar.gz" -C data/minecraft-java
                
                if [[ "$USE_BEDROCK" == "true" && -f "$BACKUP_DIR/minecraft_bedrock_$selected_backup.tar.gz" ]]; then
                    echo -e "${YELLOW}Restoring Minecraft Bedrock world...${NC}"
                    rm -rf data/minecraft-bedrock/*
                    tar -xzf "$BACKUP_DIR/minecraft_bedrock_$selected_backup.tar.gz" -C data/minecraft-bedrock
                fi
                
                echo -e "${YELLOW}Starting Docker containers...${NC}"
                docker-compose up -d
            else
                handle_error "Backup files not found in selected backup" "restore"
            fi
        fi
        
    elif [[ "$ORCHESTRATION" == "swarm" ]]; then
        # Restore remote Docker Swarm volumes
        if [[ ! -f "static_ip.ini" ]]; then
            handle_error "Inventory file static_ip.ini not found" "restore"
        fi
        
        # Get manager node from inventory
        MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
        
        if [[ -n "$MANAGER_IP" ]]; then
            echo -e "${YELLOW}Connecting to manager node $MANAGER_IP for restore...${NC}"
            
            # Create a temporary directory for selected backup
            ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "mkdir -p /tmp/minecraft-restore" || handle_error "Failed to create temp directory on remote server" "restore"
            
            # Copy backup to remote server
            echo -e "${YELLOW}Uploading backup to remote server...${NC}"
            if [[ -d "$BACKUP_DIR/$selected_backup" ]]; then
                scp $SSH_OPTS -i ssh_keys/instance1.pem "$BACKUP_DIR/$selected_backup/"*.tar.gz "ubuntu@$MANAGER_IP:/tmp/minecraft-restore/" || handle_error "Failed to upload backup" "restore"
            else
                scp $SSH_OPTS -i ssh_keys/instance1.pem "$BACKUP_DIR/minecraft_java_$selected_backup.tar.gz" "ubuntu@$MANAGER_IP:/tmp/minecraft-restore/" || handle_error "Failed to upload backup" "restore"
                
                if [[ "$USE_BEDROCK" == "true" && -f "$BACKUP_DIR/minecraft_bedrock_$selected_backup.tar.gz" ]]; then
                    scp $SSH_OPTS -i ssh_keys/instance1.pem "$BACKUP_DIR/minecraft_bedrock_$selected_backup.tar.gz" "ubuntu@$MANAGER_IP:/tmp/minecraft-restore/" || handle_error "Failed to upload Bedrock backup" "restore"
                fi
            fi
            
            # Create and execute a restore script on the remote server
            cat > /tmp/remote-restore.sh << EOF
#!/bin/bash
# Stop Minecraft services
docker service scale Mineclifford_minecraft-java=0
if docker service ls | grep -q Mineclifford_minecraft-bedrock; then
    docker service scale Mineclifford_minecraft-bedrock=0
fi

# Wait for services to stop
echo "Waiting for services to stop..."
sleep 10

# Backup current world just in case
timestamp=\$(date +%Y%m%d_%H%M%S)
mkdir -p /home/ubuntu/minecraft-backups
docker run --rm -v mineclifford_minecraft_java_data:/data -v /home/ubuntu/minecraft-backups:/backup \
    alpine tar -czf /backup/minecraft_java_pre_restore_\$timestamp.tar.gz -C /data .

if docker volume ls | grep -q mineclifford_minecraft_bedrock_data; then
    docker run --rm -v mineclifford_minecraft_bedrock_data:/data -v /home/ubuntu/minecraft-backups:/backup \
        alpine tar -czf /backup/minecraft_bedrock_pre_restore_\$timestamp.tar.gz -C /data .
fi

# Clear current world data
echo "Clearing current world data..."
docker run --rm -v mineclifford_minecraft_java_data:/data alpine sh -c "rm -rf /data/*"

if docker volume ls | grep -q mineclifford_minecraft_bedrock_data; then
    docker run --rm -v mineclifford_minecraft_bedrock_data:/data alpine sh -c "rm -rf /data/*"
fi

# Restore from backup
echo "Restoring from backup..."
for f in /tmp/minecraft-restore/minecraft_java_*.tar.gz; do
    if [[ -f "\$f" ]]; then
        docker run --rm -v mineclifford_minecraft_java_data:/data -v /tmp/minecraft-restore:/backup \
            alpine tar -xzf "/backup/\$(basename \$f)" -C /data
        break  # Only use the first file found
    fi
done

for f in /tmp/minecraft-restore/minecraft_bedrock_*.tar.gz; do
    if [[ -f "\$f" && -n "\$(docker volume ls | grep mineclifford_minecraft_bedrock_data)" ]]; then
        docker run --rm -v mineclifford_minecraft_bedrock_data:/data -v /tmp/minecraft-restore:/backup \
            alpine tar -xzf "/backup/\$(basename \$f)" -C /data
        break  # Only use the first file found
    fi
done

# Restart services
echo "Restarting services..."
docker service scale Mineclifford_minecraft-java=1
if docker service ls | grep -q Mineclifford_minecraft-bedrock; then
    docker service scale Mineclifford_minecraft-bedrock=1
fi

# Clean up
rm -rf /tmp/minecraft-restore
EOF
            
            # Upload and execute the restore script
            scp $SSH_OPTS -i ssh_keys/instance1.pem /tmp/remote-restore.sh "ubuntu@$MANAGER_IP:/tmp/remote-restore.sh" || handle_error "Failed to upload restore script" "restore"
            ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "chmod +x /tmp/remote-restore.sh && /tmp/remote-restore.sh" || handle_error "Remote restore failed" "restore"
            
        else
            handle_error "Could not find manager IP in inventory" "restore"
        fi
        
    elif [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        # Restore Kubernetes volumes
        echo -e "${YELLOW}Restoring Kubernetes volumes...${NC}"
        
        # Create restore script
        cat > /tmp/k8s-restore.sh << EOF
#!/bin/bash
# Scale down deployments
kubectl scale deployment minecraft-java --replicas=0 -n $NAMESPACE
if kubectl get deployment minecraft-bedrock -n $NAMESPACE &>/dev/null; then
    kubectl scale deployment minecraft-bedrock --replicas=0 -n $NAMESPACE
fi

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod --selector=app=minecraft-java -n $NAMESPACE --timeout=120s || true

# Create temporary pod for Java restore
cat << 'EOL' | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Pod
metadata:
  name: minecraft-restore-java
  namespace: $NAMESPACE
spec:
  volumes:
  - name: minecraft-data
    persistentVolumeClaim:
      claimName: minecraft-java-pvc
  containers:
  - name: restore
    image: alpine:latest
    command: ["sh", "-c", "rm -rf /data/* && sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: minecraft-data
EOL

# Wait for restoration pod to be ready
echo "Waiting for restoration pod to be ready..."
kubectl wait --for=condition=Ready pod/minecraft-restore-java -n $NAMESPACE --timeout=60s || true

# Copy backup to the pod
echo "Copying Java backup to pod..."
backup_file=""
if [[ -d "$BACKUP_DIR/$selected_backup" ]]; then
    backup_file=\$(ls -1 "$BACKUP_DIR/$selected_backup"/minecraft_java_*.tar.gz 2>/dev/null | head -n 1)
else
    backup_file="$BACKUP_DIR/minecraft_java_$selected_backup.tar.gz"
fi

if [[ -f "\$backup_file" ]]; then
    kubectl cp "\$backup_file" $NAMESPACE/minecraft-restore-java:/tmp/backup.tar.gz
    kubectl exec -n $NAMESPACE minecraft-restore-java -- tar -xzf /tmp/backup.tar.gz -C /data
    echo "Java backup restored successfully"
else
    echo "ERROR: Java backup file not found"
    exit 1
fi

# Delete the temporary pod
kubectl delete pod minecraft-restore-java -n $NAMESPACE

# If Bedrock is enabled, restore it too
if kubectl get deployment minecraft-bedrock -n $NAMESPACE &>/dev/null; then
    # Create temporary pod for Bedrock restore
    cat << 'EOL' | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Pod
metadata:
  name: minecraft-restore-bedrock
  namespace: $NAMESPACE
spec:
  volumes:
  - name: minecraft-data
    persistentVolumeClaim:
      claimName: minecraft-bedrock-pvc
  containers:
  - name: restore
    image: alpine:latest
    command: ["sh", "-c", "rm -rf /data/* && sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: minecraft-data
EOL

    # Wait for restoration pod to be ready
    echo "Waiting for Bedrock restoration pod to be ready..."
    kubectl wait --for=condition=Ready pod/minecraft-restore-bedrock -n $NAMESPACE --timeout=60s || true

    # Copy backup to the pod
    echo "Copying Bedrock backup to pod..."
    bedrock_backup_file=""
    if [[ -d "$BACKUP_DIR/$selected_backup" ]]; then
        bedrock_backup_file=\$(ls -1 "$BACKUP_DIR/$selected_backup"/minecraft_bedrock_*.tar.gz 2>/dev/null | head -n 1)
    else
        bedrock_backup_file="$BACKUP_DIR/minecraft_bedrock_$selected_backup.tar.gz"
    fi

    if [[ -f "\$bedrock_backup_file" ]]; then
        kubectl cp "\$bedrock_backup_file" $NAMESPACE/minecraft-restore-bedrock:/tmp/backup.tar.gz
        kubectl exec -n $NAMESPACE minecraft-restore-bedrock -- tar -xzf /tmp/backup.tar.gz -C /data
        echo "Bedrock backup restored successfully"
    else
        echo "WARNING: Bedrock backup file not found, skipping Bedrock restore"
    fi

    # Delete the temporary pod
    kubectl delete pod minecraft-restore-bedrock -n $NAMESPACE
fi

# Scale up deployments again
kubectl scale deployment minecraft-java --replicas=1 -n $NAMESPACE
if kubectl get deployment minecraft-bedrock -n $NAMESPACE &>/dev/null; then
    kubectl scale deployment minecraft-bedrock --replicas=1 -n $NAMESPACE
fi

echo "Restoration complete. Waiting for pods to start..."
kubectl get pods -n $NAMESPACE -w
EOF
        
        # Make the script executable
        chmod +x /tmp/k8s-restore.sh
        
        # Run the restore script
        /tmp/k8s-restore.sh || handle_error "Kubernetes restore failed" "restore"
        
        # Clean up
        rm /tmp/k8s-restore.sh
    fi
    
    echo -e "${GREEN}Restore completed successfully.${NC}"
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
                
                # Check logs
                echo -e "${YELLOW}Checking Java server logs (last 10 lines):${NC}"
                ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker service logs Mineclifford_minecraft-java --tail 10" || echo -e "${YELLOW}Could not fetch Java server logs${NC}"
                
                if [[ "$USE_BEDROCK" == "true" ]]; then
                    echo -e "${YELLOW}Checking Bedrock server logs (last 10 lines):${NC}"
                    ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker service logs Mineclifford_minecraft-bedrock --tail 10" || echo -e "${YELLOW}Could not fetch Bedrock server logs${NC}"
                fi
                
                # Check node status
                echo -e "${YELLOW}Checking Docker Swarm node status:${NC}"
                ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker node ls" || echo -e "${YELLOW}Could not fetch node status${NC}"
                
                # Get connection information
                echo -e "${YELLOW}Connection Information:${NC}"
                echo -e "Java Server: $MANAGER_IP:25565"
                if [[ "$USE_BEDROCK" == "true" ]]; then
                    echo -e "Bedrock Server: $MANAGER_IP:19132 (UDP)"
                fi
                echo -e "Grafana Dashboard: http://$MANAGER_IP:3000 (admin/admin)"
                echo -e "Prometheus: http://$MANAGER_IP:9090"
                echo -e "RCON Web Admin: http://$MANAGER_IP:4326 (admin/minecraft)"
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
            
            # Check logs
            echo -e "${YELLOW}Checking Java server logs (last 10 lines):${NC}"
            JAVA_POD=$(kubectl get pod -l app=minecraft-java -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
            if [[ -n "$JAVA_POD" ]]; then
                kubectl logs -n $NAMESPACE $JAVA_POD --tail=10 || echo -e "${YELLOW}Could not fetch Java server logs${NC}"
            else
                echo -e "${YELLOW}Java server pod not found${NC}"
            fi
            
            if [[ "$USE_BEDROCK" == "true" ]]; then
                echo -e "${YELLOW}Checking Bedrock server logs (last 10 lines):${NC}"
                BEDROCK_POD=$(kubectl get pod -l app=minecraft-bedrock -n $NAMESPACE -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
                if [[ -n "$BEDROCK_POD" ]]; then
                    kubectl logs -n $NAMESPACE $BEDROCK_POD --tail=10 || echo -e "${YELLOW}Could not fetch Bedrock server logs${NC}"
                else
                    echo -e "${YELLOW}Bedrock server pod not found${NC}"
                fi
            fi
            
            # Get connection information
            echo -e "${YELLOW}Connection Information:${NC}"
            JAVA_IP=$(kubectl get service minecraft-java -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null)
            JAVA_HOSTNAME=$(kubectl get service minecraft-java -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null)
            
            if [[ -n "$JAVA_IP" ]]; then
                echo -e "Java Server: $JAVA_IP:25565"
            elif [[ -n "$JAVA_HOSTNAME" ]]; then
                echo -e "Java Server: $JAVA_HOSTNAME:25565"
            else
                echo -e "Java Server: Could not determine address, service may still be provisioning"
            fi
            
            if [[ "$USE_BEDROCK" == "true" ]]; then
                BEDROCK_IP=$(kubectl get service minecraft-bedrock -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null)
                BEDROCK_HOSTNAME=$(kubectl get service minecraft-bedrock -n $NAMESPACE -o jsonpath="{.status.loadBalancer.ingress[0].hostname}" 2>/dev/null)
                
                if [[ -n "$BEDROCK_IP" ]]; then
                    echo -e "Bedrock Server: $BEDROCK_IP:19132 (UDP)"
                elif [[ -n "$BEDROCK_HOSTNAME" ]]; then
                    echo -e "Bedrock Server: $BEDROCK_HOSTNAME:19132 (UDP)"
                else
                    echo -e "Bedrock Server: Could not determine address, service may still be provisioning"
                fi
            fi
            
            # Get dashboard information
            GRAFANA_URL=$(kubectl get ingress -n $NAMESPACE -o jsonpath="{.items[?(@.metadata.name=='grafana')].spec.rules[0].host}" 2>/dev/null)
            if [[ -n "$GRAFANA_URL" ]]; then
                echo -e "Grafana Dashboard: https://$GRAFANA_URL (admin/admin)"
            else
                echo -e "Grafana Dashboard: Not exposed via Ingress"
            fi
            
            PROMETHEUS_URL=$(kubectl get ingress -n $NAMESPACE -o jsonpath="{.items[?(@.metadata.name=='prometheus')].spec.rules[0].host}" 2>/dev/null)
            if [[ -n "$PROMETHEUS_URL" ]]; then
                echo -e "Prometheus: https://$PROMETHEUS_URL"
            else
                echo -e "Prometheus: Not exposed via Ingress"
            fi
        else
            handle_error "kubectl is not installed" "status"
        fi
    fi
    
    echo -e "${GREEN}Status check completed.${NC}"
}

# Destroy infrastructure
function destroy_infrastructure {
    echo -e "${BLUE}Destroying Minecraft infrastructure...${NC}"
    
    if [[ "$INTERACTIVE" == "true" && "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${RED}WARNING: This will destroy all resources. There is NO UNDO.${NC}"
        echo -e "${YELLOW}Do you really want to destroy all resources? Type 'yes' to confirm.${NC}"
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            echo -e "${YELLOW}Destruction aborted.${NC}"
            exit 0
        fi
    fi
    
    if [[ "$ORCHESTRATION" == "local" ]]; then
        # Destroy local Docker containers
        echo -e "${YELLOW}Stopping and removing Docker containers...${NC}"
        docker-compose down -v || handle_error "Failed to stop Docker containers" "destroy"
        
        # Remove data directories if forced
        if [[ "$FORCE_CLEANUP" == "true" ]]; then
            echo -e "${YELLOW}Removing data directories...${NC}"
            rm -rf data/
        fi
        
    elif [[ "$ORCHESTRATION" == "swarm" || "$ORCHESTRATION" == "kubernetes" ]]; then
        # Based on provider, call the right terraform destroy
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
        
        # For Swarm, first remove the Docker stack
        if [[ "$ORCHESTRATION" == "swarm" && -f "static_ip.ini" ]]; then
            MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
            if [[ -n "$MANAGER_IP" ]]; then
                echo -e "${YELLOW}Removing Docker stack from $MANAGER_IP...${NC}"
                ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker stack rm Mineclifford" || echo -e "${YELLOW}Failed to remove Docker stack, continuing with destroy...${NC}"
            fi
        fi
        
        # For Kubernetes, remove the namespace
        if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
            echo -e "${YELLOW}Removing Kubernetes namespace $NAMESPACE...${NC}"
            kubectl delete namespace $NAMESPACE || echo -e "${YELLOW}Failed to remove Kubernetes namespace, continuing with destroy...${NC}"
        fi
        
        # Run Terraform destroy
        echo -e "${YELLOW}Destroying infrastructure with Terraform...${NC}"
        cd "$tf_dir" || handle_error "Failed to change to directory $tf_dir" "destroy"
        terraform destroy -auto-approve || handle_error "Terraform destroy failed" "destroy"
        cd - > /dev/null
        
        # Run the verify-destruction.sh script
        echo -e "${YELLOW}Verifying destruction...${NC}"
        ./verify-destruction.sh --provider $PROVIDER ${FORCE_CLEANUP:+--force} || handle_error "Failed to verify destruction" "destroy"
    fi
    
    echo -e "${GREEN}Infrastructure destroyed successfully.${NC}"
    
    # Remove success marker files
    rm -f .minecraft_deployment .minecraft_k8s_deployment
}

# Function to deploy Minecraft infrastructure
function deploy_infrastructure {
    echo -e "${BLUE}Starting Minecraft deployment with the following configuration:${NC}"
    echo -e "Provider: ${BLUE}$PROVIDER${NC}"
    echo -e "Orchestration: ${BLUE}$ORCHESTRATION${NC}"
    if [[ "$ORCHESTRATION" == "kubernetes" ]]; then
        echo -e "Kubernetes Provider: ${BLUE}$KUBERNETES_PROVIDER${NC}"
    fi
    echo -e "Server Names: ${BLUE}${SERVER_NAMES[*]}${NC}"
    echo -e "Version: ${BLUE}$MINECRAFT_VERSION${NC}"
    echo -e "Mode: ${BLUE}$MINECRAFT_MODE${NC}"
    echo -e "Difficulty: ${BLUE}$MINECRAFT_DIFFICULTY${NC}"
    echo -e "Log file: ${BLUE}$DEPLOYMENT_LOG${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    # Show connection information
    check_status
}

# Parse command line arguments
# First parameter is the action
if [[ $# -gt 0 && "$1" =~ ^(deploy|destroy|status|save-state|load-state|backup|restore)$ ]]; then
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
        -sn|--server-names)
            IFS=',' read -r -a SERVER_NAMES <<< "$2"
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
    backup)
        backup_worlds
        ;;
    restore)
        restore_worlds
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        show_help
        ;;
esac

exit 0