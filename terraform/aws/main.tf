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
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
  }
}

