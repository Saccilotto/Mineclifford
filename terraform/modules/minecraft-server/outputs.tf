/**
 * # Outputs for the Minecraft Server Module
 *
 * This file defines standardized outputs for the Minecraft server
 * infrastructure module that work consistently across providers.
 */

# Public IPs of the instances (provider-agnostic)
output "instance_public_ips" {
  description = "Map of instance names to their public IPs"
  value = local.is_aws ? (
    module.aws_implementation[0].instance_public_ips
  ) : (
    module.azure_implementation[0].vm_public_ips
  )
}

# SSH private keys (provider-agnostic, sensitive)
output "instance_ssh_private_keys" {
  description = "Map of instance names to their SSH private keys"
  value       = module.ssh_keys.private_keys
  sensitive   = true
}

# Provider-specific outputs that may be useful for specific contexts

# AWS-specific outputs
output "aws_vpc_id" {
  description = "AWS VPC ID (only for AWS provider)"
  value       = local.is_aws ? module.aws_implementation[0].vpc_id : null
}

output "aws_subnet_id" {
  description = "AWS Subnet ID (only for AWS provider)"
  value       = local.is_aws ? module.aws_implementation[0].subnet_id : null
}

output "aws_security_group_id" {
  description = "AWS Security Group ID (only for AWS provider)"
  value       = local.is_aws ? module.aws_implementation[0].security_group_id : null
}

# Azure-specific outputs
output "azure_resource_group_name" {
  description = "Azure Resource Group name (only for Azure provider)"
  value       = local.is_azure ? module.azure_implementation[0].resource_group_name : null
}

output "azure_vnet_name" {
  description = "Azure VNet name (only for Azure provider)"
  value       = local.is_azure ? module.azure_implementation[0].vnet_name : null
}

output "azure_subnet_id" {
  description = "Azure Subnet ID (only for Azure provider)"
  value       = local.is_azure ? module.azure_implementation[0].subnet_id : null
}

# Common inventory output
output "inventory_content" {
  description = "Content of the generated Ansible inventory file"
  value       = module.inventory.inventory_content
}