#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define test directories
SCRIPT_TESTS="script-tests"
TERRAFORM_TESTS="terraform-tests"
KUBERNETES_TESTS="kubernetes-tests"
ALL_TEST_DIRS=("$SCRIPT_TESTS" "$TERRAFORM_TESTS" "$KUBERNETES_TESTS")

# Command line options
TEST_TYPE="all"
VERBOSE=false

# Help function
function show_help {
    echo -e "${BLUE}Mineclifford Testing Framework${NC}"
    echo -e "Runs tests for various components of the Mineclifford project."
    echo -e ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo -e ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -t, --type TYPE      Type of tests to run (all, script, terraform, kubernetes)"
    echo -e "  -v, --verbose        Enable verbose output"
    echo -e "  -h, --help           Show this help message"
    echo -e ""
    echo -e "${YELLOW}Examples:${NC}"
    echo -e "  $0 --type script"
    echo -e "  $0 --type terraform --verbose"
    echo -e ""
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Function to run script tests
function run_script_tests {
    echo -e "${BLUE}Running script tests...${NC}"
    
    # Check if BATS is installed
    if ! command -v bats &> /dev/null; then
        echo -e "${RED}Error: BATS (Bash Automated Testing System) is not installed.${NC}"
        echo -e "${YELLOW}Install it with: npm install -g bats${NC}"
        return 1
    fi
    
    # Create test directory if it doesn't exist
    mkdir -p "$SCRIPT_TESTS"
    
    # If verbose mode is enabled, pass -v flag to bats
    if [[ "$VERBOSE" == "true" ]]; then
        BATS_OPTS="-v"
    else
        BATS_OPTS=""
    fi
    
    # Run all .bats files in the script tests directory
    bats $BATS_OPTS "$SCRIPT_TESTS"/*.bats
    return $?
}

# Function to run Terraform tests
function run_terraform_tests {
    echo -e "${BLUE}Running Terraform tests...${NC}"
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}Error: Terraform is not installed.${NC}"
        return 1
    fi
    
    # Create test directory if it doesn't exist
    mkdir -p "$TERRAFORM_TESTS"
    
    TEST_RESULT=0
    
    # Test AWS Terraform configuration
    echo -e "${YELLOW}Testing AWS Terraform configuration...${NC}"
    cd ../terraform/aws || return 1
    
    terraform init -backend=false
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}AWS Terraform initialization failed${NC}"
        TEST_RESULT=1
    fi
    
    terraform validate
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}AWS Terraform validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}AWS Terraform validation passed${NC}"
    fi
    
    # Return to tests directory
    cd ../../tests || return 1
    
    # Test Azure Terraform configuration
    echo -e "${YELLOW}Testing Azure Terraform configuration...${NC}"
    cd ../terraform/azure || return 1
    
    terraform init -backend=false
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}Azure Terraform initialization failed${NC}"
        TEST_RESULT=1
    fi
    
    terraform validate
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}Azure Terraform validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}Azure Terraform validation passed${NC}"
    fi
    
    # Return to tests directory
    cd ../../tests || return 1
    
    # Test Terraform modules
    echo -e "${YELLOW}Testing Terraform modules...${NC}"
    cd ../terraform/modules/minecraft-server || return 1
    
    terraform init -backend=false
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}Terraform module initialization failed${NC}"
        TEST_RESULT=1
    fi
    
    terraform validate
    TF_RESULT=$?
    if [[ $TF_RESULT -ne 0 ]]; then
        echo -e "${RED}Terraform module validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}Terraform module validation passed${NC}"
    fi
    
    # Return to tests directory
    cd ../../../tests || return 1
    
    return $TEST_RESULT
}

# Function to run Kubernetes tests
function run_kubernetes_tests {
    echo -e "${BLUE}Running Kubernetes tests...${NC}"
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed.${NC}"
        return 1
    fi
    
    # Create test directory if it doesn't exist
    mkdir -p "$KUBERNETES_TESTS"
    
    TEST_RESULT=0
    
    # Test Kubernetes base manifests
    echo -e "${YELLOW}Testing Kubernetes base manifests...${NC}"
    if ! kubectl apply --dry-run=client -f ../deployment/kubernetes/base/; then
        echo -e "${RED}Kubernetes base manifests validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}Kubernetes base manifests validation passed${NC}"
    fi
    
    # Test Kubernetes AWS overlay
    echo -e "${YELLOW}Testing Kubernetes AWS overlay...${NC}"
    if ! kubectl kustomize ../deployment/kubernetes/aws/ >/dev/null; then
        echo -e "${RED}Kubernetes AWS overlay validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}Kubernetes AWS overlay validation passed${NC}"
    fi
    
    # Test Kubernetes Azure overlay
    echo -e "${YELLOW}Testing Kubernetes Azure overlay...${NC}"
    if ! kubectl kustomize ../deployment/kubernetes/azure/ >/dev/null; then
        echo -e "${RED}Kubernetes Azure overlay validation failed${NC}"
        TEST_RESULT=1
    else
        echo -e "${GREEN}Kubernetes Azure overlay validation passed${NC}"
    fi
    
    return $TEST_RESULT
}

# Main function to run tests
function run_tests {
    # Create test directories if they don't exist
    for dir in "${ALL_TEST_DIRS[@]}"; do
        mkdir -p "$dir"
    done
    
    # Track overall success/failure
    OVERALL_RESULT=0
    
    case "$TEST_TYPE" in
        all)
            run_script_tests
            if [[ $? -ne 0 ]]; then
                OVERALL_RESULT=1
            fi
            
            run_terraform_tests
            if [[ $? -ne 0 ]]; then
                OVERALL_RESULT=1
            fi
            
            run_kubernetes_tests
            if [[ $? -ne 0 ]]; then
                OVERALL_RESULT=1
            fi
            ;;
        script)
            run_script_tests
            OVERALL_RESULT=$?
            ;;
        terraform)
            run_terraform_tests
            OVERALL_RESULT=$?
            ;;
        kubernetes)
            run_kubernetes_tests
            OVERALL_RESULT=$?
            ;;
        *)
            echo -e "${RED}Invalid test type: $TEST_TYPE${NC}"
            echo -e "${YELLOW}Valid options: all, script, terraform, kubernetes${NC}"
            exit 1
            ;;
    esac
    
    # Print overall result
    if [[ $OVERALL_RESULT -eq 0 ]]; then
        echo -e "${GREEN}All tests passed successfully!${NC}"
    else
        echo -e "${RED}Some tests failed. See above for details.${NC}"
    fi
    
    return $OVERALL_RESULT
}

# Ensure we're in the tests directory
cd "$(dirname "$0")" || exit 1

# Run the tests
run_tests
exit $?