#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROVIDER="aws"
KUBERNETES_PROVIDER="eks"  # Options: eks, aks
SKIP_INFRASTRUCTURE=false
INTERACTIVE=true
DEPLOYMENT_LOG="mineclifford_k8s_deployment_$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_ENABLED=true
MINECRAFT_VERSION="latest"
MINECRAFT_MODE="survival"
MINECRAFT_DIFFICULTY="normal"
USE_BEDROCK=true
NAMESPACE="mineclifford"

# Create log file
touch $DEPLOYMENT_LOG
exec > >(tee -a $DEPLOYMENT_LOG)
exec 2>&1

# Function to show help
function show_help {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -p, --provider <aws|azure|gcp>   Cloud provider (default: aws)"
    echo -e "  -k, --k8s <eks|aks|gke|k3s>      Kubernetes provider (default: eks)"
    echo -e "  -s, --skip-infrastructure        Skip infrastructure provisioning"
    echo -e "  -n, --namespace NAMESPACE        Kubernetes namespace (default: mineclifford)"
    echo -e "  -v, --minecraft-version VERSION  Specify Minecraft version (default: latest)"
    echo -e "  -m, --mode <survival|creative>   Game mode (default: survival)"
    echo -e "  -d, --difficulty <peaceful|easy|normal|hard> Game difficulty (default: normal)"
    echo -e "  -b, --no-bedrock                 Skip Bedrock Edition deployment"
    echo -e "      --no-interactive             Run in non-interactive mode"
    echo -e "      --no-rollback                Disable rollback on failure"
    echo -e "  -h, --help                       Show this help message"
    echo -e "${YELLOW}Example:${NC}"
    echo -e "  $0 --provider aws --k8s eks --minecraft-version 1.19 --mode creative"
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
            "infrastructure")
                echo -e "${YELLOW}Rolling back infrastructure changes...${NC}"
                if [[ "$PROVIDER" == "aws" ]]; then
                    cd terraform/aws/kubernetes
                    terraform destroy -auto-approve
                elif [[ "$PROVIDER" == "azure" ]]; then
                    cd terraform/azure/kubernetes
                    terraform destroy -auto-approve
                elif [[ "$PROVIDER" == "gcp" ]]; then
                    cd terraform/gcp/kubernetes
                    terraform destroy -auto-approve
                fi
                cd ../../..
                ;;
            "kubernetes")
                echo -e "${YELLOW}Rolling back Kubernetes deployments...${NC}"
                kubectl delete -f deployment/kubernetes/minecraft-java-deployment.yaml --namespace=$NAMESPACE
                kubectl delete -f deployment/kubernetes/minecraft-bedrock-deployment.yaml --namespace=$NAMESPACE
                kubectl delete -f deployment/kubernetes/monitoring.yaml --namespace=$NAMESPACE
                kubectl delete -f deployment/kubernetes/ingress.yaml --namespace=$NAMESPACE
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
    for cmd in terraform kubectl jq; do
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
        
        if [[ "$KUBERNETES_PROVIDER" == "eks" ]]; then
            if ! command -v eksctl &> /dev/null; then
                echo -e "${RED}Error: eksctl is not installed.${NC}"
                handle_error "Missing required tool: eksctl" "pre-deployment"
            fi
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        if ! command -v az &> /dev/null; then
            echo -e "${RED}Error: Azure CLI is not installed.${NC}"
            handle_error "Missing required tool: az" "pre-deployment"
        fi
        
        echo -e "${YELLOW}Validating Azure credentials...${NC}"
        if ! az account show &> /dev/null; then
            handle_error "Invalid Azure credentials" "pre-deployment"
        fi
    elif [[ "$PROVIDER" == "gcp" ]]; then
        if ! command -v gcloud &> /dev/null; then
            echo -e "${RED}Error: Google Cloud SDK is not installed.${NC}"
            handle_error "Missing required tool: gcloud" "pre-deployment"
        fi
        
        echo -e "${YELLOW}Validating GCP credentials...${NC}"
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
            handle_error "Invalid GCP credentials" "pre-deployment"
        fi
    fi

    echo -e "${GREEN}Environment validation passed.${NC}"
}

# Create or update Kubernetes cluster
function provision_infrastructure {
    if [[ "$SKIP_INFRASTRUCTURE" == "true" ]]; then
        echo -e "${YELLOW}Skipping infrastructure provisioning as requested.${NC}"
        return
    fi
    
    echo -e "${BLUE}Provisioning Kubernetes cluster with $KUBERNETES_PROVIDER on $PROVIDER...${NC}"
    
    # Determine directory based on provider
    local tf_dir=""
    if [[ "$PROVIDER" == "aws" ]]; then
        tf_dir="terraform/aws/kubernetes"
    elif [[ "$PROVIDER" == "azure" ]]; then
        tf_dir="terraform/azure/kubernetes"
    elif [[ "$PROVIDER" == "gcp" ]]; then
        tf_dir="terraform/gcp/kubernetes"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p $tf_dir
    
    # Create Terraform configuration for Kubernetes cluster
    if [[ "$PROVIDER" == "aws" && "$KUBERNETES_PROVIDER" == "eks" ]]; then
        # Create EKS cluster using eksctl (simpler than Terraform for EKS)
        echo -e "${YELLOW}Creating EKS cluster...${NC}"
        
        cat > eksctl-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: mineclifford-cluster
  region: us-east-2
  version: "1.27"
nodeGroups:
  - name: ng-1
    instanceType: t3.large
    desiredCapacity: 2
    minSize: 1
    maxSize: 3
    volumeSize: 80
    privateNetworking: false
    ssh:
      allow: true
    labels: {role: worker}
    tags:
      nodegroup-role: worker
EOF
        
        eksctl create cluster -f eksctl-config.yaml || handle_error "Failed to create EKS cluster" "infrastructure"
        aws eks update-kubeconfig --name mineclifford-cluster --region us-east-2
        
    elif [[ "$PROVIDER" == "azure" && "$KUBERNETES_PROVIDER" == "aks" ]]; then
        # Create AKS cluster using Azure CLI
        echo -e "${YELLOW}Creating AKS cluster...${NC}"
        
        # Create resource group
        az group create --name mineclifford-rg --location eastus2 || handle_error "Failed to create resource group" "infrastructure"
        
        # Create AKS cluster
        az aks create \
            --resource-group mineclifford-rg \
            --name mineclifford-cluster \
            --node-count 2 \
            --node-vm-size Standard_DS2_v2 \
            --enable-addons monitoring \
            --generate-ssh-keys || handle_error "Failed to create AKS cluster" "infrastructure"
        
        # Get credentials
        az aks get-credentials --resource-group mineclifford-rg --name mineclifford-cluster
        
    elif [[ "$KUBERNETES_PROVIDER" == "k3s" ]]; then
        # K3s setup is more appropriate for standalone or local execution
        echo -e "${YELLOW}Setting up K3s...${NC}"
        curl -sfL https://get.k3s.io | sh - || handle_error "Failed to install K3s" "infrastructure"
        
        # Wait for K3s to be ready
        sleep 10
        mkdir -p $HOME/.kube
        sudo cat /etc/rancher/k3s/k3s.yaml > $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        export KUBECONFIG=$HOME/.kube/config
    fi
    
    echo -e "${GREEN}Kubernetes infrastructure provisioned successfully.${NC}"
    
    # Verify kubectl connectivity
    if ! kubectl get nodes; then
        handle_error "Failed to connect to Kubernetes cluster" "infrastructure"
    fi
}

# Deploy Minecraft to Kubernetes
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

# Verify deployment
function verify_deployment {
    echo -e "${BLUE}Verifying Minecraft deployment...${NC}"
    
    # Wait for pods to be ready
    echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
    kubectl wait --for=condition=Ready pods --all --namespace=$NAMESPACE --timeout=300s
    
    # Get service endpoints
    echo -e "${YELLOW}Getting service endpoints...${NC}"
    
    # Java server endpoint
    JAVA_SERVICE_IP=$(kubectl get service minecraft-java --namespace=$NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ -z "$JAVA_SERVICE_IP" ]]; then
        JAVA_SERVICE_IP=$(kubectl get service minecraft-java --namespace=$NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi
    
    # Bedrock server endpoint if enabled
    if [[ "$USE_BEDROCK" == "true" ]]; then
        BEDROCK_SERVICE_IP=$(kubectl get service minecraft-bedrock --namespace=$NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [[ -z "$BEDROCK_SERVICE_IP" ]]; then
            BEDROCK_SERVICE_IP=$(kubectl get service minecraft-bedrock --namespace=$NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        fi
    fi
    
    # Display connection information
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}Minecraft Server Information:${NC}"
    echo -e "${GREEN}Java Edition:${NC}"
    echo -e "  ${YELLOW}Server address: ${JAVA_SERVICE_IP}:25565${NC}"
    
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "${GREEN}Bedrock Edition:${NC}"
        echo -e "  ${YELLOW}Server address: ${BEDROCK_SERVICE_IP}${NC}"
        echo -e "  ${YELLOW}Port: 19132 (UDP)${NC}"
    fi
    
    echo -e "${GREEN}Monitoring:${NC}"
    echo -e "  ${YELLOW}Grafana: http://monitor.your-domain.com${NC}"
    echo -e "  ${YELLOW}Prometheus: http://metrics.your-domain.com${NC}"
    
    echo -e "${BLUE}To view Minecraft Java logs:${NC}"
    echo -e "  ${YELLOW}kubectl logs -f -l app=minecraft-java --namespace=$NAMESPACE${NC}"
    
    if [[ "$USE_BEDROCK" == "true" ]]; then
        echo -e "${BLUE}To view Minecraft Bedrock logs:${NC}"
        echo -e "  ${YELLOW}kubectl logs -f -l app=minecraft-bedrock --namespace=$NAMESPACE${NC}"
    fi
    
    echo -e "${GREEN}==========================================${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -k|--k8s)
            KUBERNETES_PROVIDER="$2"
            shift 2
            ;;
        -s|--skip-infrastructure)
            SKIP_INFRASTRUCTURE=true
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
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

# Validate parameters
if [[ ! "$MINECRAFT_MODE" =~ ^(survival|creative|adventure|spectator)$ ]]; then
    echo -e "${RED}Error: Invalid game mode. Must be one of: survival, creative, adventure, spectator${NC}"
    exit 1
fi

if [[ ! "$MINECRAFT_DIFFICULTY" =~ ^(peaceful|easy|normal|hard)$ ]]; then
    echo -e "${RED}Error: Invalid difficulty. Must be one of: peaceful, easy, normal, hard${NC}"
    exit 1
fi

if [[ ! "$PROVIDER" =~ ^(aws|azure|gcp)$ ]]; then
    echo -e "${RED}Error: Invalid provider. Must be one of: aws, azure, gcp${NC}"
    exit 1
fi

if [[ ! "$KUBERNETES_PROVIDER" =~ ^(eks|aks|gke|k3s)$ ]]; then
    echo -e "${RED}Error: Invalid Kubernetes provider. Must be one of: eks, aks, gke, k3s${NC}"
    exit 1
fi

# Main execution flow
echo -e "${BLUE}Starting Mineclifford Kubernetes deployment with the following configuration:${NC}"
echo -e "Provider: ${YELLOW}$PROVIDER${NC}"
echo -e "Kubernetes Provider: ${YELLOW}$KUBERNETES_PROVIDER${NC}"
echo -e "Kubernetes Namespace: ${YELLOW}$NAMESPACE${NC}"
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
provision_infrastructure
deploy_to_kubernetes
verify_deployment

# Save successful deployment marker
echo "$(date) - Kubernetes Minecraft $MINECRAFT_VERSION - $MINECRAFT_MODE mode - $MINECRAFT_DIFFICULTY difficulty" > .minecraft_k8s_deployment

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Minecraft Kubernetes deployment completed successfully!${NC}"
echo -e "${GREEN}Provider: $PROVIDER ($KUBERNETES_PROVIDER)${NC}"
echo -e "${GREEN}Version: $MINECRAFT_VERSION${NC}"
echo -e "${GREEN}Mode: $MINECRAFT_MODE${NC}"
echo -e "${GREEN}Difficulty: $MINECRAFT_DIFFICULTY${NC}"
echo -e "${GREEN}Log file: $DEPLOYMENT_LOG${NC}"
echo -e "${GREEN}==========================================${NC}"

exit 0