#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help function
function show_help {
    echo -e "${BLUE}Usage: ./destroy.sh [OPTIONS]${NC}"
    echo -e "Destroy infrastructure on AWS or Azure using a specific Terraform state file"
    echo ""
    echo -e "Options:"
    echo -e "  -p, --provider    Specify cloud provider (aws or azure), default: aws"
    echo -e "  -s, --state       Path to an existing tfstate file to use (optional)"
    echo -e "  -y, --yes         Auto-approve destruction (no confirmation prompt)"
    echo -e "  -h, --help        Show this help message"
    echo ""
    echo -e "Example: ./destroy.sh --provider aws --state ./my-terraform.tfstate"
}

# Default values
PROVIDER="aws"
STATE_FILE=""
AUTO_APPROVE=false

# Pre-destruction cleanup
function pre_destroy_cleanup() {
    echo -e "${YELLOW}Performing pre-destruction cleanup for $PROVIDER...${NC}"
    
    if [[ "$PROVIDER" == "aws" ]]; then
        # Get all managed VPC IDs from the state file
        VPC_IDS=$(terraform state list | grep aws_vpc | xargs -I{} terraform state show {} | grep "id =" | awk -F'"' '{print $2}')
        
        for VPC_ID in $VPC_IDS; do
            echo -e "${BLUE}Cleaning up resources in VPC $VPC_ID${NC}"
            
            # Clean up VPC endpoints
            echo -e "Removing VPC endpoints..."
            aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[*].VpcEndpointId" --output text | xargs -r -I{} aws ec2 delete-vpc-endpoint --vpc-endpoint-id {}
            
            # Clean up any elastic network interfaces
            echo -e "Checking for orphaned network interfaces..."
            aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" --output text | xargs -r -I{} aws ec2 delete-network-interface --network-interface-id {}
            
            # Check for any NAT gateways
            echo -e "Checking for NAT gateways..."
            aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[?State!='deleted'].NatGatewayId" --output text | xargs -r -I{} aws ec2 delete-nat-gateway --nat-gateway-id {}
        done
        
        # Look for any detached EBS volumes
        echo -e "${BLUE}Checking for orphaned EBS volumes...${NC}"
        aws ec2 describe-volumes --filters "Name=status,Values=available" --query "Volumes[*].VolumeId" --output text | xargs -r -I{} aws ec2 delete-volume --volume-id {}
        
    elif [[ "$PROVIDER" == "azure" ]]; then
        # Get resource group names from state
        RESOURCE_GROUPS=$(terraform state list | grep azurerm_resource_group | xargs -I{} terraform state show {} | grep "name =" | awk -F'"' '{print $2}')
        
        for RG in $RESOURCE_GROUPS; do
            echo -e "${BLUE}Cleaning up resources in resource group $RG${NC}"
            
            # Clean up any orphaned network interfaces
            echo -e "Checking for orphaned network interfaces..."
            az network nic list --resource-group "$RG" --query "[?provisioningState=='Succeeded'].id" -o tsv | xargs -r -I{} az network nic delete --ids {} --no-wait
            
            # Remove any custom role assignments
            echo -e "Removing custom role assignments..."
            az role assignment list --resource-group "$RG" --query "[].id" -o tsv | xargs -r -I{} az role assignment delete --ids {} --no-wait
        done
    fi
}

# Post-destruction verification
function post_destroy_verification() {
    echo -e "${YELLOW}Verifying destruction of resources...${NC}"
    
    if [[ "$PROVIDER" == "aws" ]]; then
        # Look for any VPCs we might have managed
        VPC_TAG="cp-planta"
        remaining_vpcs=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*${VPC_TAG}*" --query "Vpcs[*].VpcId" --output text)
        
        if [[ -n "$remaining_vpcs" ]]; then
            echo -e "${RED}Found remaining VPCs that may belong to the project:${NC}"
            echo "$remaining_vpcs"
            
            if [[ "$AUTO_APPROVE" == "true" ]]; then
                echo -e "${YELLOW}Auto-approve enabled. Attempting to force delete remaining VPCs...${NC}"
                for vpc in $remaining_vpcs; do
                    aws ec2 delete-vpc --vpc-id "$vpc" || echo -e "${RED}Could not delete VPC $vpc. It may have dependencies.${NC}"
                done
            else
                echo -e "${YELLOW}Would you like to force delete these VPCs? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    for vpc in $remaining_vpcs; do
                        aws ec2 delete-vpc --vpc-id "$vpc" || echo -e "${RED}Could not delete VPC $vpc. It may have dependencies.${NC}"
                    done
                fi
            fi
        else
            echo -e "${GREEN}No remaining VPCs found with tag pattern *${VPC_TAG}*${NC}"
        fi
        
    elif [[ "$PROVIDER" == "azure" ]]; then
        # Look for any resource groups we might have managed
        RG_PREFIX="cp-planta"
        remaining_rgs=$(az group list --query "[?starts_with(name, '${RG_PREFIX}')].name" -o tsv)
        
        if [[ -n "$remaining_rgs" ]]; then
            echo -e "${RED}Found remaining resource groups that may belong to the project:${NC}"
            echo "$remaining_rgs"
            
            if [[ "$AUTO_APPROVE" == "true" ]]; then
                echo -e "${YELLOW}Auto-approve enabled. Attempting to force delete remaining resource groups...${NC}"
                for rg in $remaining_rgs; do
                    az group delete --name "$rg" --yes --no-wait
                done
            else
                echo -e "${YELLOW}Would you like to force delete these resource groups? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    for rg in $remaining_rgs; do
                        az group delete --name "$rg" --yes --no-wait
                    done
                fi
            fi
        else
            echo -e "${GREEN}No remaining resource groups found with prefix ${RG_PREFIX}${NC}"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -s|--state)
            STATE_FILE="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_APPROVE=true
            shift
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

# Set project vars from .env file if it exists
if [[ -f .env ]]; then
    echo -e "${YELLOW}Loading environment variables from .env file...${NC}"
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        export "$line"
    done < .env
    
    # Export Terraform-specific variables
    if [[ "$PROVIDER" == "azure" ]]; then
        export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
    fi
fi

# Determine the Terraform directory based on provider
if [[ "$PROVIDER" == "aws" ]]; then
    TF_DIR="terraform/aws"
elif [[ "$PROVIDER" == "azure" ]]; then
    TF_DIR="terraform/azure"
else
    echo -e "${RED}Error: Invalid provider specified. Use 'aws' or 'azure'.${NC}"
    exit 1
fi

# Create a temporary directory for state file if needed
if [[ -n "$STATE_FILE" ]]; then
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${RED}Error: Specified state file does not exist: $STATE_FILE${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Using provided state file: $STATE_FILE${NC}"
    
    # Create temp directory for state operations
    TEMP_DIR=$(mktemp -d)
    STATE_FILENAME=$(basename "$STATE_FILE")
    
    # Copy the state file to the temp directory
    cp "$STATE_FILE" "$TEMP_DIR/$STATE_FILENAME"
    
    # If the state file isn't named terraform.tfstate, rename it
    if [[ "$STATE_FILENAME" != "terraform.tfstate" ]]; then
        mv "$TEMP_DIR/$STATE_FILENAME" "$TEMP_DIR/terraform.tfstate"
    fi
fi

# Check if the Terraform directory exists
if [[ ! -d "$TF_DIR" ]]; then
    echo -e "${RED}Error: Terraform directory not found: $TF_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Preparing to destroy infrastructure in $TF_DIR...${NC}"

# Navigate to the Terraform directory
cd "$TF_DIR"

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Copy the state file if provided
if [[ -n "$STATE_FILE" ]]; then
    # Copy the state file from temp directory
    cp "$TEMP_DIR/terraform.tfstate" .
    echo -e "${YELLOW}Terraform state file copied.${NC}"
fi

# Show what will be destroyed
echo -e "${YELLOW}Generating destroy plan...${NC}"
terraform plan -destroy -out=destroy.tfplan

# Confirm destruction if auto-approve is not set
if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo -e "${RED}WARNING: This will destroy all resources managed by this Terraform configuration.${NC}"
    echo -e "${RED}There is NO UNDO. Resources will be permanently DELETED.${NC}"
    echo -e "${YELLOW}Do you really want to destroy all resources?${NC}"
    echo -e "  Type ${GREEN}yes${NC} to confirm."
    
    read -p "Enter response: " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        echo -e "${YELLOW}Destruction aborted.${NC}"
        exit 0
    fi
fi

pre_destroy_cleanup

# Destroy resources
echo -e "${YELLOW}Destroying infrastructure...${NC}"
terraform apply destroy.tfplan

# Check if destroy was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Infrastructure successfully destroyed!${NC}"
    
    # Clean up state in parent directory if we were using a custom state
    if [[ -n "$STATE_FILE" ]]; then
        # If the directory has a terraform.tfstate, it's because we placed it there and should clean it up
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -rf "$TEMP_DIR"
    fi
else
    echo -e "${RED}Failed to destroy infrastructure. Check the error messages above.${NC}"
    exit 1
fi

post_destroy_verification

cd ..
echo -e "${GREEN}All done!${NC}"
exit 0