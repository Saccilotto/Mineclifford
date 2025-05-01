/**
 * # Minecraft Server Module
 *
 * This module creates a Minecraft server infrastructure with provider-agnostic interfaces.
 * It supports both AWS and Azure as cloud providers and enables consistent configuration
 * across different environments.
 */

locals {
  # Common local variables
  is_aws   = var.provider == "aws"
  is_azure = var.provider == "azure"
  
  # Ensure server names are always in the expected format
  normalized_server_names = [
    for name in var.server_names : lower(replace(name, "/[^a-zA-Z0-9-]/", "-"))
  ]
  
  # Common tags that will be applied to all resources
  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}

# SSH Key generation is provider-agnostic
module "ssh_keys" {
  source         = "../common/ssh-keys"
  instance_names = local.normalized_server_names
  keys_path      = var.ssh_keys_path
}

# Invoke the proper provider-specific module based on the provider variable
module "aws_implementation" {
  count  = local.is_aws ? 1 : 0
  source = "./aws"
  
  # Pass through common variables
  server_names      = local.normalized_server_names
  instance_type     = var.instance_type
  region            = var.region
  public_key_data   = module.ssh_keys.public_keys
  tags              = local.common_tags
  project_name      = var.project_name
  
  # AWS-specific variables
  vpc_cidr          = var.vpc_cidr
  subnet_cidr       = var.subnet_cidr
  username          = var.username
}

module "azure_implementation" {
  count  = local.is_azure ? 1 : 0
  source = "./azure"
  
  # Pass through common variables
  server_names         = local.normalized_server_names
  vm_size              = var.instance_type
  location             = var.region
  public_key_data      = module.ssh_keys.public_keys
  tags                 = local.common_tags
  project_name         = var.project_name
  
  # Azure-specific variables
  resource_group_name  = var.resource_group_name
  address_space        = var.vpc_cidr != "" ? [var.vpc_cidr] : ["10.0.0.0/16"]
  subnet_prefixes      = var.subnet_cidr != "" ? [var.subnet_cidr] : ["10.0.1.0/24"]
  username             = var.username
  subscription_id      = var.subscription_id
}

# Common inventory generation
module "inventory" {
  source = "../common/inventory"
  
  instance_details = local.is_aws ? (
    module.aws_implementation[0].instance_public_ips
  ) : (
    module.azure_implementation[0].vm_public_ips
  )
  
  ssh_user = var.username
  inventory_path = var.inventory_path
  
  depends_on = [
    module.aws_implementation,
    module.azure_implementation
  ]
}