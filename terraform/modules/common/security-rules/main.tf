// terraform/modules/common/security-rules/main.tf
variable "environment_name" {
  description = "Environment name for naming resources"
  type        = string
  default     = "mineclifford"
}

variable "project_tags" {
  description = "Project tags to be applied to all resources"
  type        = map(string)
  default     = {
    Project     = "mineclifford"
    ManagedBy   = "terraform"
    Owner       = "dell"
  }
}

# Common service ports used in both AWS and Azure
locals {
  common_tcp_ports = {
    ssh                = 22,
    http               = 80,
    postgres           = 5432,
    dns_tcp            = 53,
    mongodb            = 27017
  }
  
  common_udp_ports = {
    dns_udp            = 53
  }
  
  # Generate numbered tcp rules starting at priority 100
  tcp_rules_with_priority = {
    for i, name in keys(local.common_tcp_ports) : name => {
      port = local.common_tcp_ports[name]
      priority = 100 + i
      name = name  
    }
  }
  
  # Same for UDP starting at priority 300
  udp_rules_with_priority = {
    for i, name in keys(local.common_udp_ports) : name => {
      port = local.common_udp_ports[name]
      priority = 300 + i
      name = name  
    }
  }
  
  # Common tags that will be applied to all resources
  all_tags = merge(
    var.project_tags,
    {
      Environment = var.environment_name
    }
  )
}

output "common_tcp_ports" {
  value = local.common_tcp_ports
}

output "common_udp_ports" {
  value = local.common_udp_ports
}

output "tcp_rules_with_priority" {
  value = local.tcp_rules_with_priority
}

output "udp_rules_with_priority" {
  value = local.udp_rules_with_priority
}

output "environment_name" {
  value = var.environment_name
}

output "resource_tags" {
  value = local.all_tags
}