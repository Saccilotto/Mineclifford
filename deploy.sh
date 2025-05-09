#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Default values
IMPORT_WORLD=""
FORCE_VERSION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --import-world)
      IMPORT_WORLD="$2"
      shift 2
      ;;
    --force-version)
      FORCE_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo -e "${YELLOW}Starting Minecraft server deployment...${NC}"

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Apply Terraform configuration
echo -e "${YELLOW}Applying Terraform configuration...${NC}"
terraform apply -auto-approve

# Wait for SSH to become available
echo -e "${YELLOW}Waiting for SSH to become available...${NC}"
public_ip=$(terraform output -raw public_ip)
until ssh -i minecraft_key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$public_ip "echo SSH is up"; do
  echo "Waiting for SSH to become available..."
  sleep 5
done

# Run Ansible playbook
ANSIBLE_EXTRA=""
if [ -n "$IMPORT_WORLD" ]; then
  ANSIBLE_EXTRA="$ANSIBLE_EXTRA import_world=$IMPORT_WORLD"
fi
if [ -n "$FORCE_VERSION" ]; then
  ANSIBLE_EXTRA="$ANSIBLE_EXTRA force_version=$FORCE_VERSION"
fi

echo -e "${YELLOW}Running Ansible playbook...${NC}"
if [ -n "$ANSIBLE_EXTRA" ]; then
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini minecraft_setup.yml -e "$ANSIBLE_EXTRA"
else
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini minecraft_setup.yml
fi

# Done
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${GREEN}$(terraform output minecraft_connect)${NC}"
echo -e "${GREEN}SSH: $(terraform output ssh_command)${NC}"