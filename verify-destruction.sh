#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROVIDER="aws"
FORCE_CLEANUP=false

# Help function
function show_help {
    echo -e "${BLUE}Usage: ./verify-destruction.sh [OPTIONS]${NC}"
    echo -e "Verify and clean up any resources that might have survived Terraform destruction"
    echo ""
    echo -e "Options:"
    echo -e "  -p, --provider    Specify cloud provider (aws or azure), default: aws"
    echo -e "  -f, --force       Force cleanup of detected resources without prompting"
    echo -e "  -h, --help        Show this help message"
    echo ""
    echo -e "Example: ./verify-destruction.sh --provider aws --force"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_CLEANUP=true
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
fi

echo -e "${BLUE}Verifying complete destruction of resources for provider: $PROVIDER${NC}"

if [[ "$PROVIDER" == "aws" ]]; then
    echo -e "${YELLOW}Checking for AWS resources...${NC}"
    
    # Check for project-specific resources by tag
    PROJECT_TAG="cp-planta"
    
    # Check VPCs
    echo -e "${BLUE}Checking for VPCs...${NC}"
    VPC_IDS=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*${PROJECT_TAG}*" --query "Vpcs[*].VpcId" --output text)
    
    if [[ -n "$VPC_IDS" ]]; then
        echo -e "${RED}Found VPCs that might belong to the project:${NC}"
        for vpc in $VPC_IDS; do
            echo "- $vpc"
            # Get VPC details
            aws ec2 describe-vpcs --vpc-ids "$vpc" --query "Vpcs[*].{VPCID:VpcId,CIDR:CidrBlock,Name:Tags[?Key=='Name'].Value|[0]}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Attempting to delete VPC $vpc...${NC}"
                # First cleanup dependencies
                # 1. Network interfaces
                echo "Cleaning up network interfaces..."
                NI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
                for ni in $NI_IDS; do
                    aws ec2 delete-network-interface --network-interface-id "$ni"
                done
                
                # 2. Subnets
                echo "Cleaning up subnets..."
                SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[*].SubnetId" --output text)
                for subnet in $SUBNET_IDS; do
                    aws ec2 delete-subnet --subnet-id "$subnet"
                done
                
                # 3. Route tables
                echo "Cleaning up route tables..."
                RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[*].RouteTableId" --output text)
                for rt in $RT_IDS; do
                    if [[ "$rt" == *"rtb-"* ]]; then  # Skip main route table
                        ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[*].Associations[*].RouteTableAssociationId" --output text)
                        for assoc in $ASSOC_IDS; do
                            if [[ -n "$assoc" ]]; then
                                aws ec2 disassociate-route-table --association-id "$assoc"
                            fi
                        done
                        aws ec2 delete-route-table --route-table-id "$rt"
                    fi
                done
                
                # 4. Internet gateways
                echo "Cleaning up internet gateways..."
                IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[*].InternetGatewayId" --output text)
                for igw in $IGW_IDS; do
                    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"
                    aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
                done
                
                # 5. Security groups (skip default)
                echo "Cleaning up security groups..."
                SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
                for sg in $SG_IDS; do
                    aws ec2 delete-security-group --group-id "$sg"
                done
                
                # Finally try to delete the VPC
                aws ec2 delete-vpc --vpc-id "$vpc"
            else
                echo -e "${YELLOW}Would you like to delete this VPC and all its resources? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Cleaning up VPC $vpc..."
                    # 1. Network interfaces
                    echo "Cleaning up network interfaces..."
                    NI_IDS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
                    for ni in $NI_IDS; do
                        aws ec2 delete-network-interface --network-interface-id "$ni"
                    done
                    
                    # 2. Subnets
                    echo "Cleaning up subnets..."
                    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "Subnets[*].SubnetId" --output text)
                    for subnet in $SUBNET_IDS; do
                        aws ec2 delete-subnet --subnet-id "$subnet"
                    done
                    
                    # 3. Route tables
                    echo "Cleaning up route tables..."
                    RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --query "RouteTables[*].RouteTableId" --output text)
                    for rt in $RT_IDS; do
                        if [[ "$rt" == *"rtb-"* ]]; then  # Skip main route table
                            ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --query "RouteTables[*].Associations[*].RouteTableAssociationId" --output text)
                            for assoc in $ASSOC_IDS; do
                                if [[ -n "$assoc" ]]; then
                                    aws ec2 disassociate-route-table --association-id "$assoc"
                                fi
                            done
                            aws ec2 delete-route-table --route-table-id "$rt"
                        fi
                    done
                    
                    # 4. Internet gateways
                    echo "Cleaning up internet gateways..."
                    IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[*].InternetGatewayId" --output text)
                    for igw in $IGW_IDS; do
                        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"
                        aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
                    done
                    
                    # 5. Security groups (skip default)
                    echo "Cleaning up security groups..."
                    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
                    for sg in $SG_IDS; do
                        aws ec2 delete-security-group --group-id "$sg"
                    done
                    
                    # Finally try to delete the VPC
                    aws ec2 delete-vpc --vpc-id "$vpc"
                fi
            fi
        done
    else
        echo -e "${GREEN}No VPCs found with tag pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for EC2 instances
    echo -e "${BLUE}Checking for EC2 instances...${NC}"
    INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*${PROJECT_TAG}*" "Name=instance-state-name,Values=running,stopped,stopping,pending" --query "Reservations[*].Instances[*].InstanceId" --output text)
    
    if [[ -n "$INSTANCE_IDS" ]]; then
        echo -e "${RED}Found EC2 instances that might belong to the project:${NC}"
        for instance in $INSTANCE_IDS; do
            echo "- $instance"
            # Get instance details
            aws ec2 describe-instances --instance-ids "$instance" --query "Reservations[*].Instances[*].{InstanceId:InstanceId,InstanceType:InstanceType,State:State.Name,Name:Tags[?Key=='Name'].Value|[0]}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Terminating instance $instance...${NC}"
                aws ec2 terminate-instances --instance-ids "$instance"
                echo "Waiting for instance to terminate..."
                aws ec2 wait instance-terminated --instance-ids "$instance"
            else
                echo -e "${YELLOW}Would you like to terminate this instance? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Terminating instance $instance..."
                    aws ec2 terminate-instances --instance-ids "$instance"
                    echo "Waiting for instance to terminate..."
                    aws ec2 wait instance-terminated --instance-ids "$instance"
                fi
            fi
        done
    else
        echo -e "${GREEN}No EC2 instances found with tag pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for Elastic IPs
    echo -e "${BLUE}Checking for Elastic IPs...${NC}"
    EIP_IDS=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=*${PROJECT_TAG}*" --query "Addresses[*].AllocationId" --output text)
    
    if [[ -n "$EIP_IDS" ]]; then
        echo -e "${RED}Found Elastic IPs that might belong to the project:${NC}"
        for eip in $EIP_IDS; do
            echo "- $eip"
            # Get EIP details
            aws ec2 describe-addresses --allocation-ids "$eip" --query "Addresses[*].{AllocationId:AllocationId,PublicIp:PublicIp,InstanceId:InstanceId}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Releasing Elastic IP $eip...${NC}"
                aws ec2 release-address --allocation-id "$eip"
            else
                echo -e "${YELLOW}Would you like to release this Elastic IP? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Releasing Elastic IP $eip..."
                    aws ec2 release-address --allocation-id "$eip"
                fi
            fi
        done
    else
        echo -e "${GREEN}No Elastic IPs found with tag pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for Security Groups
    echo -e "${BLUE}Checking for Security Groups...${NC}"
    SG_IDS=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=*${PROJECT_TAG}*" "Name=group-name,Values=!default" --query "SecurityGroups[*].GroupId" --output text)
    
    if [[ -n "$SG_IDS" ]]; then
        echo -e "${RED}Found Security Groups that might belong to the project:${NC}"
        for sg in $SG_IDS; do
            echo "- $sg"
            # Get SG details
            aws ec2 describe-security-groups --group-ids "$sg" --query "SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting Security Group $sg...${NC}"
                aws ec2 delete-security-group --group-id "$sg"
            else
                echo -e "${YELLOW}Would you like to delete this Security Group? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting Security Group $sg..."
                    aws ec2 delete-security-group --group-id "$sg"
                fi
            fi
        done
    else
        echo -e "${GREEN}No Security Groups found with tag pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for Volume resources (EBS)
    echo -e "${BLUE}Checking for EBS volumes...${NC}"
    VOLUME_IDS=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=*${PROJECT_TAG}*" --query "Volumes[*].VolumeId" --output text)
    
    if [[ -n "$VOLUME_IDS" ]]; then
        echo -e "${RED}Found EBS volumes that might belong to the project:${NC}"
        for volume in $VOLUME_IDS; do
            echo "- $volume"
            # Get volume details
            aws ec2 describe-volumes --volume-ids "$volume" --query "Volumes[*].{VolumeId:VolumeId,Size:Size,State:State,InstanceId:Attachments[0].InstanceId}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting EBS volume $volume...${NC}"
                aws ec2 delete-volume --volume-id "$volume"
            else
                echo -e "${YELLOW}Would you like to delete this EBS volume? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting EBS volume $volume..."
                    aws ec2 delete-volume --volume-id "$volume"
                fi
            fi
        done
    else
        echo -e "${GREEN}No EBS volumes found with tag pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for Load Balancers
    echo -e "${BLUE}Checking for Load Balancers...${NC}"
    LB_ARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(to_string(Tags[?Key=='Name'].Value), '${PROJECT_TAG}')].LoadBalancerArn" --output text)
    
    if [[ -n "$LB_ARNS" ]]; then
        echo -e "${RED}Found Load Balancers that might belong to the project:${NC}"
        for lb in $LB_ARNS; do
            echo "- $lb"
            # Get LB details
            aws elbv2 describe-load-balancers --load-balancer-arns "$lb" --query "LoadBalancers[*].{Name:LoadBalancerName,DNSName:DNSName,Type:Type,State:State.Code}" --output table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting Load Balancer $lb...${NC}"
                aws elbv2 delete-load-balancer --load-balancer-arn "$lb"
            else
                echo -e "${YELLOW}Would you like to delete this Load Balancer? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting Load Balancer $lb..."
                    aws elbv2 delete-load-balancer --load-balancer-arn "$lb"
                fi
            fi
        done
    else
        echo -e "${GREEN}No Load Balancers found with tag pattern *${PROJECT_TAG}*${NC}"
    fi

elif [[ "$PROVIDER" == "azure" ]]; then
    echo -e "${YELLOW}Checking for Azure resources...${NC}"
    
    # Check for resource groups with the project tag/name pattern
    PROJECT_TAG="cp-planta"
    
    # Check for Resource Groups
    echo -e "${BLUE}Checking for Resource Groups...${NC}"
    RG_LIST=$(az group list --query "[?contains(name, '${PROJECT_TAG}')].name" -o tsv)
    
    if [[ -n "$RG_LIST" ]]; then
        echo -e "${RED}Found Resource Groups that might belong to the project:${NC}"
        for rg in $RG_LIST; do
            echo "- $rg"
            # Get resource group details
            az group show --name "$rg" --query "{Name:name,Location:location,Tags:tags}" -o table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting Resource Group $rg...${NC}"
                az group delete --name "$rg" --yes --no-wait
            else
                echo -e "${YELLOW}Would you like to delete this Resource Group? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting Resource Group $rg..."
                    az group delete --name "$rg" --yes --no-wait
                fi
            fi
        done
    else
        echo -e "${GREEN}No Resource Groups found with name pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for unattached resources that might have been missed by resource group deletion
    echo -e "${BLUE}Checking for unattached disks...${NC}"
    DISK_IDS=$(az disk list --query "[?contains(name, '${PROJECT_TAG}') && diskState=='Unattached'].id" -o tsv)
    
    if [[ -n "$DISK_IDS" ]]; then
        echo -e "${RED}Found unattached disks that might belong to the project:${NC}"
        for disk in $DISK_IDS; do
            echo "- $disk"
            # Get disk details
            az disk show --ids "$disk" --query "{Name:name,Size:diskSizeGb,State:diskState}" -o table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting unattached disk $disk...${NC}"
                az disk delete --ids "$disk" --yes
            else
                echo -e "${YELLOW}Would you like to delete this unattached disk? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting unattached disk $disk..."
                    az disk delete --ids "$disk" --yes
                fi
            fi
        done
    else
        echo -e "${GREEN}No unattached disks found with name pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for public IPs
    echo -e "${BLUE}Checking for unattached public IPs...${NC}"
    IP_IDS=$(az network public-ip list --query "[?contains(name, '${PROJECT_TAG}') && ipConfiguration==null].id" -o tsv)
    
    if [[ -n "$IP_IDS" ]]; then
        echo -e "${RED}Found unattached public IPs that might belong to the project:${NC}"
        for ip in $IP_IDS; do
            echo "- $ip"
            # Get IP details
            az network public-ip show --ids "$ip" --query "{Name:name,IPAddress:ipAddress,AllocationMethod:publicIpAllocationMethod}" -o table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting unattached public IP $ip...${NC}"
                az network public-ip delete --ids "$ip"
            else
                echo -e "${YELLOW}Would you like to delete this unattached public IP? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting unattached public IP $ip..."
                    az network public-ip delete --ids "$ip"
                fi
            fi
        done
    else
        echo -e "${GREEN}No unattached public IPs found with name pattern *${PROJECT_TAG}*${NC}"
    fi
    
    # Check for network security groups
    echo -e "${BLUE}Checking for unused network security groups...${NC}"
    NSG_IDS=$(az network nsg list --query "[?contains(name, '${PROJECT_TAG}') && networkInterfaces==null && subnets==null].id" -o tsv)
    
    if [[ -n "$NSG_IDS" ]]; then
        echo -e "${RED}Found unused network security groups that might belong to the project:${NC}"
        for nsg in $NSG_IDS; do
            echo "- $nsg"
            # Get NSG details
            az network nsg show --ids "$nsg" --query "{Name:name,Location:location,ResourceGroup:resourceGroup}" -o table
            
            # Prompt for cleanup or force cleanup
            if [[ "$FORCE_CLEANUP" == "true" ]]; then
                echo -e "${YELLOW}Force cleanup enabled. Deleting unused network security group $nsg...${NC}"
                az network nsg delete --ids "$nsg"
            else
                echo -e "${YELLOW}Would you like to delete this unused network security group? (y/N)${NC}"
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "Deleting unused network security group $nsg..."
                    az network nsg delete --ids "$nsg"
                fi
            fi
        done
    else
        echo -e "${GREEN}No unused network security groups found with name pattern *${PROJECT_TAG}*${NC}"
    fi
else
    echo -e "${RED}Error: Unsupported provider. This script only supports 'aws' or 'azure'.${NC}"
    exit 1
fi

echo -e "${GREEN}Resource verification completed.${NC}"

exit 0