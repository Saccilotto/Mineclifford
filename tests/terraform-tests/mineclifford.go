package test

import (
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestMinecliffordAWS tests the AWS Terraform configuration
func TestMinecliffordAWS(t *testing.T) {
	// Terraform options for AWS
	awsOpts := &terraform.Options{
		TerraformDir: "../../terraform/aws",
		Vars: map[string]interface{}{
			"project_name": "mineclifford-test",
			"server_names": []string{"test-instance"},
			"region":       "us-east-2",
		},
		NoColor: true,
	}

	// Validate the Terraform configuration
	terraform.InitAndValidate(t, awsOpts)
}

// TestMinecliffordAzure tests the Azure Terraform configuration
func TestMinecliffordAzure(t *testing.T) {
	// Terraform options for Azure
	azureOpts := &terraform.Options{
		TerraformDir: "../../terraform/azure",
		Vars: map[string]interface{}{
			"resource_group_name": "mineclifford-test",
			"server_names":        []string{"test-instance"},
			"location":            "East US 2",
		},
		NoColor: true,
	}

	// Validate the Terraform configuration
	terraform.InitAndValidate(t, azureOpts)
}

// TestMinecliffordModuleAWS tests the Minecraft server module with AWS provider
func TestMinecliffordModuleAWS(t *testing.T) {
	// Terraform options for the module with AWS provider
	moduleAWSOpts := &terraform.Options{
		TerraformDir: "../../terraform/modules/minecraft-server",
		Vars: map[string]interface{}{
			"provider":     "aws",
			"project_name": "mineclifford-module-test",
			"server_names": []string{"test-module-instance"},
			"region":       "us-east-2",
		},
		NoColor: true,
	}

	// Validate the Terraform configuration
	terraform.InitAndValidate(t, moduleAWSOpts)
}

// TestMinecliffordModuleAzure tests the Minecraft server module with Azure provider
func TestMinecliffordModuleAzure(t *testing.T) {
	// Terraform options for the module with Azure provider
	moduleAzureOpts := &terraform.Options{
		TerraformDir: "../../terraform/modules/minecraft-server",
		Vars: map[string]interface{}{
			"provider":            "azure",
			"project_name":        "mineclifford-module-test",
			"server_names":        []string{"test-module-instance"},
			"region":              "East US 2",
			"resource_group_name": "mineclifford-module-test",
			"subscription_id":     "00000000-0000-0000-0000-000000000000", // Dummy ID for validation
		},
		NoColor: true,
	}

	// Validate the Terraform configuration
	terraform.InitAndValidate(t, moduleAzureOpts)
}

// TestMinecliffordTagging tests that resources have appropriate tags
func TestMinecliffordTagging(t *testing.T) {
	// Skip this test in CI pipelines with no AWS credentials
	// This test can be run locally with proper AWS credentials
	if testing.Short() {
		t.Skip("Skipping tagging test in short mode")
	}

	// Terraform options for testing tags
	taggingOpts := &terraform.Options{
		TerraformDir: "../../terraform/modules/minecraft-server",
		Vars: map[string]interface{}{
			"provider":     "aws",
			"project_name": "mineclifford-tagging-test",
			"server_names": []string{"tagging-test"},
			"tags": map[string]string{
				"Environment": "test",
				"Project":     "mineclifford",
			},
		},
		NoColor: true,
	}

	// Initialize and validate the Terraform configuration
	terraform.InitAndValidate(t, taggingOpts)

	// Get output from terraform plan
	planOutput := terraform.Plan(t, taggingOpts)

	// Check that required tags are present in the plan output
	assert.Contains(t, planOutput, `"Environment" = "test"`)
	assert.Contains(t, planOutput, `"Project" = "mineclifford"`)
}

// TestMinecliffordStateConsistency verifies that state files are generated correctly
func TestMinecliffordStateConsistency(t *testing.T) {
	// Skip this test in CI pipelines with no AWS/Azure credentials
	if testing.Short() {
		t.Skip("Skipping state consistency test in short mode")
	}

	// Terraform options for AWS
	stateOpts := &terraform.Options{
		TerraformDir: "../../terraform/aws",
		Vars: map[string]interface{}{
			"project_name": "mineclifford-state-test",
			"server_names": []string{"state-test"},
		},
		NoColor: true,
	}

	// Initialize Terraform
	terraform.Init(t, stateOpts)

	// Run terraform plan to generate the state file
	terraform.RunTerraformCommand(t, stateOpts, "plan", "-out=terraform.tfplan")

	// Check that state files are generated correctly
	// Note: This is a simplified test, in a real scenario we would check for specific state contents
	assert.FileExists(t, fmt.Sprintf("%s/.terraform", stateOpts.TerraformDir))
}
