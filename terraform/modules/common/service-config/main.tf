variable "env_prefix" {
  description = "Environment prefix for naming"
  type        = string
  default     = "mineclifford"
}

# Common service configurations
locals {
  services = {
    # your service = {
    #   subdomain    = "your-service",
    #   port         = 5050
    # }
  }
}

output "services" {
  value = local.services
}

output "stack_prefix" {
  value = var.env_prefix
}