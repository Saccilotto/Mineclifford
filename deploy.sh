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
DEPLOYMENT_LOG="deployment_$(date +%Y%m%d_%H%M%S).log"
ROLLBACK_ENABLED=true

# Create log file
touch $DEPLOYMENT_LOG
exec > >(tee -a $DEPLOYMENT_LOG)
exec 2>&1

# Export environment variables for Ansible and Python
export ANSIBLE_FORCE_COLOR=true
export PYTHONIOENCODING=utf-8
# Add for direct SSH commands in the script
export ANSIBLE_HOST_KEY_CHECKING=False

# Add this block to load environment variables globally:
if [[ -f ".env" ]]; then
    echo -e "${YELLOW}Loading environment variables from .env file...${NC}"
    set -o allexport
    source .env
    set +o allexport
else
    echo -e "${YELLOW}Warning: .env file not found. Environment variables may need to be set manually.${NC}"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "==========================================="
echo "CP-Planta Deployment - $(date)"
echo "==========================================="

# Function to show help
function show_help {
    echo -e "${BLUE}Usage: $0 [OPTIONS]${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -p, --provider <aws|azure>       Specify the cloud provider (default: aws)"
    echo -e "  -s, --skip-terraform             Skip Terraform provisioning"
    echo -e "      --no-interactive             Run in non-interactive mode"
    echo -e "      --no-rollback                Disable rollback on failure"
    echo -e "  -h, --help                       Show this help message"
    echo -e "${YELLOW}Example:${NC}"
    echo -e "  $0 --provider aws --skip-terraform"
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
                    ssh $SSH_OPTS -i ssh_keys/instance1.pem ubuntu@$MANAGER_IP "docker stack rm CP-Planta"
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
    for cmd in terraform ansible-playbook aws az jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: Required tool '$cmd' is not installed.${NC}"
            handle_error "Missing required tool: $cmd" "pre-deployment"
        fi
    done
    
    # Check credentials
    if [[ "$PROVIDER" == "aws" ]]; then
        echo -e "${YELLOW}Validating AWS credentials...${NC}"
        if ! aws sts get-caller-identity &> /dev/null; then
            handle_error "Invalid AWS credentials" "pre-deployment"
        fi
    elif [[ "$PROVIDER" == "azure" ]]; then
        echo -e "${YELLOW}Validating Azure credentials...${NC}"
        # Using the Terraform prefix(TF_VAR) on var for Azure 
        if [[ "$PROVIDER" == "azure" && -n "$AZURE_SUBSCRIPTION_ID" ]]; then
            export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
        fi
        
        if ! az account show &> /dev/null; then
            handle_error "Invalid Azure credentials" "pre-deployment"
        fi
    fi
    
    # Check for required files
    if [[ ! -f ".env" ]]; then
        echo -e "${RED}Error: .env file not found.${NC}"
        handle_error "Missing .env file" "pre-deployment"
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
    echo -e "${BLUE}Running Ansible playbooks...${NC}"
    
    # Verify inventory file exists
    if [[ ! -f "static_ip.ini" ]]; then
        handle_error "Inventory file static_ip.ini not found" "ansible"
    fi
    
    # Set proper permissions for SSH keys
    echo -e "${YELLOW}Setting SSH key permissions...${NC}"
    chmod 400 ssh_keys/*.pem
    
    # Run Ansible playbook with progress
    echo -e "${YELLOW}Deploying infrastructure via Ansible...${NC}"
    cd deployment/ansible
    
    # Test connectivity
    echo -e "${YELLOW}Testing connectivity to hosts...${NC}"
    ANSIBLE_CONFIG=./playbooks/ansible.cfg ansible -i ../../static_ip.ini all -m ping || handle_error "Ansible connectivity test failed" "ansible"
    
    # Run main playbook
    echo -e "${YELLOW}Running main Swarm setup playbook...${NC}"
    ANSIBLE_CONFIG=./playbooks/ansible.cfg ansible-playbook -i ../../static_ip.ini ./playbooks/swarm_setup.yml || handle_error "Ansible playbook execution failed" "ansible"
    
    cd ../..
}

function verify_deployment {
    echo -e "${BLUE}Verifying deployment...${NC}"
    
    # Get manager node IP
    MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
    MANAGER_KEY=$(realpath "ssh_keys/instance1.pem")
    
    if [[ -z "$MANAGER_IP" ]]; then
        echo -e "${RED}Could not determine manager node IP.${NC}"
        handle_error "Manager IP resolution failed" "verification"
    fi
    
    echo -e "${YELLOW}Checking Docker Swarm status...${NC}"
    ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "docker node ls" || handle_error "Docker Swarm status check failed" "verification"
    
    echo -e "${YELLOW}Checking Docker services status...${NC}"
    ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "docker service ls" || handle_error "Docker services status check failed" "verification"
    
    update_dns_and_verify_services
}

# Update DNS records and verify service accessibility
function update_dns_and_verify_services {
    # Get manager node IP for DNS updates
    MANAGER_IP=$(grep -A1 '\[instance1\]' static_ip.ini | tail -n1 | awk '{print $1}')
    MANAGER_KEY=$(realpath "ssh_keys/instance1.pem")
    
    echo -e "${YELLOW}Updating DNS records with public IP...${NC}"

    # Get the actual public IP from the EC2 
    # For AWS
    if [[ "$PROVIDER" == "aws" ]]; then
        PUBLIC_IP=$(aws ec2 describe-addresses --filters "Name=instance-id,Values=$(ssh $SSH_OPTS -i $MANAGER_KEY ubuntu@$MANAGER_IP "curl -s http://169.254.169.254/latest/meta-data/instance-id")" --query 'Addresses[0].PublicIp' --output text)
    # For Azure
    elif [[ "$PROVIDER" == "azure" ]]; then
        az network public-ip list --resource-group cp-planta-ages --query "[].{Name:name,IPAddress:ipAddress}" -o table
        PUBLIC_IP=$(az network public-ip show --name cp-planta-public-ip-instance1 --resource-group cp-planta-ages --query ipAddress -o tsv)
    fi    

    # Source the environment for DuckDNS token
    source .env
    
    # Define domains
    DOMAINS=("cpplanta" "api.cpplanta" "pgadmin.cpplanta" "traefik.cpplanta" "viz.cpplanta")
    
    # Loop through domains and update with proper error handling
    DNS_UPDATE_FAILED=0
    for DOMAIN in "${DOMAINS[@]}"; do
        echo -e "${YELLOW}Updating $DOMAIN.duckdns.org...${NC}"
        
        # Try multiple times with backoff
        for attempt in {1..3}; do
            UPDATE_RESULT="$(curl -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$DUCKDNS_TOKEN&ip=$PUBLIC_IP")"
            
            if [ "$UPDATE_RESULT" = "OK" ]; then
                echo -e "${GREEN}Successfully updated $DOMAIN.duckdns.org to point to $PUBLIC_IP${NC}"
                break
            else
                echo -e "${YELLOW}Attempt $attempt failed to update $DOMAIN.duckdns.org: $UPDATE_RESULT${NC}"
                sleep 5
            fi
        done
        
        if [ "$UPDATE_RESULT" != "OK" ]; then
            echo -e "${RED}Failed to update $DOMAIN.duckdns.org after multiple attempts${NC}"
            DNS_UPDATE_FAILED=1
        fi
    done
    
    # Wait for DNS propagation
    echo -e "${YELLOW}Waiting for DNS propagation (100 seconds)...${NC}"
    for i in {1..100}; do
        echo -n "."
        sleep 1
        if (( i % 20 == 0 )); then
            echo " $i seconds"
        fi
    done
    echo ""
    
    # Test HTTP endpoints
    SERVICE_CHECK_FAILED=0
    for domain in cpplanta.duckdns.org api.cpplanta.duckdns.org pgadmin.cpplanta.duckdns.org; do
        echo -e "${YELLOW}Testing $domain...${NC}"
        max_retries=3
        retry_count=0
        status_code=""
        
        while [ $retry_count -lt $max_retries ]; do
            status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://$domain")
            
            if [[ "$status_code" =~ ^(200|301|302|307|308)$ ]]; then
                echo -e "${GREEN}✓ $domain is accessible (HTTP $status_code)${NC}"
                break
            else
                retry_count=$((retry_count+1))
                if [ $retry_count -ge $max_retries ]; then
                    echo -e "${RED}✗ Failed to connect to $domain after $max_retries attempts.${NC}"
                    SERVICE_CHECK_FAILED=1
                else
                    echo -e "${YELLOW}Retrying in 10 seconds (attempt $retry_count/$max_retries)...${NC}"
                    sleep 10
                fi
            fi
        done
    done
    
    if [ $DNS_UPDATE_FAILED -eq 1 ]; then
        echo -e "${YELLOW}Warning: Some DNS updates failed, but continuing with deployment.${NC}"
    fi
    
    if [ $SERVICE_CHECK_FAILED -eq 1 ]; then
        echo -e "${YELLOW}Warning: Some services failed accessibility checks.${NC}"
        echo -e "${YELLOW}This might be due to Let's Encrypt provisioning delay. Services may become available shortly.${NC}"
    else
        echo -e "${GREEN}All services are accessible!${NC}"
    fi
}


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

# Main execution flow
validate_environment

if [[ "$SKIP_TERRAFORM" != "true" ]]; then
    run_terraform
else
    echo -e "${YELLOW}Skipping Terraform provisioning as requested.${NC}"
fi

run_ansible

verify_deployment

# Save successful deployment marker
git rev-parse HEAD > .last_deployment 2>/dev/null || echo "$(date)" > .last_deployment

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}Provider: $PROVIDER${NC}"
echo -e "${GREEN}Log file: $DEPLOYMENT_LOG${NC}"
echo -e "${GREEN}==========================================${NC}"

exit 0