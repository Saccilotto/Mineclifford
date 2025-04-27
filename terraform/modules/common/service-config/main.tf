variable "env_prefix" {
  description = "Environment prefix for naming"
  type        = string
  default     = "mineclifford"
}

# Common service configurations
locals {
  services = {
    minecraft_java = {
      subdomain    = "java",
      port         = 25565,
      image        = "itzg/minecraft-server",
      version      = "latest",
      memory       = "2G",
      environment  = {
        EULA       = "TRUE",
        TYPE       = "PAPER",
        MEMORY     = "2G",
        DIFFICULTY = "normal",
        MODE       = "survival",
        MOTD       = "Mineclifford Server"
      }
    },
    minecraft_bedrock = {
      subdomain    = "bedrock",
      port         = 19132,
      image        = "itzg/minecraft-bedrock-server",
      version      = "latest",
      memory       = "1G",
      environment  = {
        EULA       = "TRUE",
        GAMEMODE   = "survival",
        DIFFICULTY = "normal",
        SERVER_NAME = "Mineclifford Bedrock"
      }
    },
    prometheus = {
      subdomain    = "metrics",
      port         = 9090,
      image        = "prom/prometheus",
      version      = "latest"
    },
    grafana = {
      subdomain    = "monitor",
      port         = 3000,
      image        = "grafana/grafana",
      version      = "latest"
    }
  }
}

output "services" {
  value = local.services
}

output "stack_prefix" {
  value = var.env_prefix
}