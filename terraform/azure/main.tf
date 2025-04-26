locals {
  common_tags = {
    Project     = "mineclifford"
    ManagedBy   = "terraform"
    Owner       = "mojang"
  }
}

terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
  }
}