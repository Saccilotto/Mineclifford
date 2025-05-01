#!/usr/bin/env bats

# Setup function that runs before each test
setup() {
  # Source the script to test its functions
  # We use a trick to source but avoid running main code
  export TEST_MODE=true
  source ../../minecraft-ops.sh
  
  # Create a temporary directory for testing
  export TEMP_DIR="$(mktemp -d)"
  
  # Mock important commands to avoid actual execution
  function terraform { echo "MOCK: terraform $*"; return 0; }
  function ansible-playbook { echo "MOCK: ansible-playbook $*"; return 0; }
  function kubectl { echo "MOCK: kubectl $*"; return 0; }
  function docker-compose { echo "MOCK: docker-compose $*"; return 0; }
  function ssh { echo "MOCK: ssh $*"; return 0; }
  
  export -f terraform
  export -f ansible-playbook
  export -f kubectl
  export -f docker-compose
  export -f ssh
}

# Teardown function that runs after each test
teardown() {
  # Remove the temporary directory
  rm -rf "$TEMP_DIR"
}

# Test the help function
@test "show_help should display usage information" {
  run show_help
  
  # Verify the output contains expected help text
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Actions:"* ]]
  [[ "$output" == *"Options:"* ]]
  [[ "$output" == *"Examples:"* ]]
}

# Test environment validation
@test "validate_environment should succeed with valid configuration" {
  # Mock commands to simulate successful validation
  function aws { echo "MOCK: aws $*"; return 0; }
  export -f aws
  
  PROVIDER="aws"
  ORCHESTRATION="swarm"
  MINECRAFT_MODE="survival"
  MINECRAFT_DIFFICULTY="normal"
  KUBERNETES_PROVIDER="eks"
  
  run validate_environment
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Environment validation passed"* ]]
}

@test "validate_environment should fail with invalid provider" {
  PROVIDER="invalid"
  ORCHESTRATION="swarm"
  MINECRAFT_MODE="survival"
  MINECRAFT_DIFFICULTY="normal"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid provider"* ]]
}

@test "validate_environment should fail with invalid orchestration" {
  PROVIDER="aws"
  ORCHESTRATION="invalid"
  MINECRAFT_MODE="survival"
  MINECRAFT_DIFFICULTY="normal"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid orchestration"* ]]
}

@test "validate_environment should fail with invalid game mode" {
  PROVIDER="aws"
  ORCHESTRATION="swarm"
  MINECRAFT_MODE="invalid"
  MINECRAFT_DIFFICULTY="normal"
  ACTION="deploy"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid game mode"* ]]
}

@test "validate_environment should fail with invalid difficulty" {
  PROVIDER="aws"
  ORCHESTRATION="swarm"
  MINECRAFT_MODE="survival"
  MINECRAFT_DIFFICULTY="invalid"
  ACTION="deploy"
  
  run validate_environment
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid difficulty"* ]]
}

# Test Terraform functions
@test "run_terraform should skip when SKIP_TERRAFORM is true" {
  SKIP_TERRAFORM=true
  PROVIDER="aws"
  ORCHESTRATION="swarm"
  
  run run_terraform
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping Terraform provisioning"* ]]
}

@test "run_terraform should execute terraform for AWS" {
  SKIP_TERRAFORM=false
  PROVIDER="aws"
  ORCHESTRATION="swarm"
  
  # Create mock directories
  mkdir -p "$TEMP_DIR/terraform/aws"
  
  # Mock cd function to avoid changing directory
  function cd { echo "MOCK: cd $*"; return 0; }
  export -f cd
  
  run run_terraform
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Running Terraform for aws"* ]]
  [[ "$output" == *"MOCK: cd terraform/aws"* ]]
  [[ "$output" == *"MOCK: terraform init"* ]]
  [[ "$output" == *"MOCK: terraform plan"* ]]
  [[ "$output" == *"MOCK: terraform apply"* ]]
}

@test "run_terraform should execute terraform for Azure" {
  SKIP_TERRAFORM=false
  PROVIDER="azure"
  ORCHESTRATION="swarm"
  
  # Create mock directories
  mkdir -p "$TEMP_DIR/terraform/azure"
  
  # Mock cd function to avoid changing directory
  function cd { echo "MOCK: cd $*"; return 0; }
  export -f cd
  
  run run_terraform
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Running Terraform for azure"* ]]
  [[ "$output" == *"MOCK: cd terraform/azure"* ]]
  [[ "$output" == *"MOCK: terraform init"* ]]
  [[ "$output" == *"MOCK: terraform plan"* ]]
  [[ "$output" == *"MOCK: terraform apply"* ]]
}

# Test deployment functions
@test "deploy_local should create docker-compose.yml" {
  MINECRAFT_VERSION="1.18"
  MINECRAFT_MODE="creative"
  MINECRAFT_DIFFICULTY="peaceful"
  MEMORY="3G"
  USE_BEDROCK=true
  
  # Mock necessary functions
  function mkdir { echo "MOCK: mkdir $*"; return 0; }
  export -f mkdir
  
  run deploy_local
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deploying Minecraft locally with Docker"* ]]
  [[ "$output" == *"Creating docker-compose.yml"* ]]
  [[ "$output" == *"Version: 1.18"* ]]
  [[ "$output" == *"Game Mode: creative"* ]]
  [[ "$output" == *"Difficulty: peaceful"* ]]
  [[ "$output" == *"Memory: 3G"* ]]
  [[ "$output" == *"MOCK: docker-compose up -d"* ]]
}

@test "deploy_to_kubernetes should deploy to Kubernetes" {
  NAMESPACE="minecraft-test"
  MINECRAFT_VERSION="1.18"
  MINECRAFT_MODE="creative"
  MINECRAFT_DIFFICULTY="peaceful"
  MEMORY="3G"
  USE_BEDROCK=true
  
  # Mock kubectl function to simulate namespace not existing
  function kubectl {
    if [[ "$1" == "get" && "$2" == "namespace" ]]; then
      return 1
    else
      echo "MOCK: kubectl $*"
      return 0
    fi
  }
  export -f kubectl
  
  # Mock sed function
  function sed { echo "MOCK: sed $*"; return 0; }
  export -f sed
  
  run deploy_to_kubernetes
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deploying Minecraft to Kubernetes"* ]]
  [[ "$output" == *"MOCK: kubectl create namespace"* ]]
  [[ "$output" == *"Configuring Minecraft deployment files"* ]]
  [[ "$output" == *"MOCK: kubectl apply"* ]]
  [[ "$output" == *"Minecraft deployed to Kubernetes successfully"* ]]
}

# Test status checking
@test "check_status should work for local deployment" {
  ORCHESTRATION="local"
  
  # Mock docker function
  function docker { echo "MOCK: docker $*"; return 0; }
  export -f docker
  
  run check_status
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking deployment status"* ]]
  [[ "$output" == *"MOCK: docker ps"* ]]
  [[ "$output" == *"Status check completed"* ]]
}

@test "check_status should work for Swarm deployment" {
  ORCHESTRATION="swarm"
  
  # Create mock inventory file
  echo -e "[instance1]\n192.168.1.100" > "$TEMP_DIR/static_ip.ini"
  cp "$TEMP_DIR/static_ip.ini" "static_ip.ini"
  
  run check_status
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking deployment status"* ]]
  [[ "$output" == *"MOCK: ssh"* ]]
  [[ "$output" == *"Status check completed"* ]]
  
  # Cleanup
  rm -f "static_ip.ini"
}

@test "check_status should work for Kubernetes deployment" {
  ORCHESTRATION="kubernetes"
  NAMESPACE="minecraft-test"
  
  run check_status
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking deployment status"* ]]
  [[ "$output" == *"MOCK: kubectl get deployments"* ]]
  [[ "$output" == *"MOCK: kubectl get services"* ]]
  [[ "$output" == *"MOCK: kubectl get pods"* ]]
  [[ "$output" == *"Status check completed"* ]]
}

# Test infrastructure destruction
@test "destroy_infrastructure should work for local deployment" {
  ORCHESTRATION="local"
  
  run destroy_infrastructure
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Destroying Minecraft infrastructure"* ]]
  [[ "$output" == *"MOCK: docker-compose down -v"* ]]
  [[ "$output" == *"Infrastructure destroyed successfully"* ]]
}

@test "destroy_infrastructure should work for cloud deployment" {
  ORCHESTRATION="swarm"
  PROVIDER="aws"
  FORCE_CLEANUP=true
  
  # Mock destroy.sh script
  function ./destroy.sh { echo "MOCK: ./destroy.sh $*"; return 0; }
  export -f ./destroy.sh
  
  # Mock verify-destruction.sh script
  function ./verify-destruction.sh { echo "MOCK: ./verify-destruction.sh $*"; return 0; }
  export -f ./verify-destruction.sh
  
  run destroy_infrastructure
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Destroying Minecraft infrastructure"* ]]
  [[ "$output" == *"MOCK: ./destroy.sh"* ]]
  [[ "$output" == *"MOCK: ./verify-destruction.sh"* ]]
  [[ "$output" == *"Infrastructure destroyed successfully"* ]]
}