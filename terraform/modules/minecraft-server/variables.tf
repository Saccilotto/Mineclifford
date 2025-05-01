/**
 * # Variables for the Minecraft Server Module
 *
 * This file defines all variables used by the provider-agnostic
 * Minecraft server infrastructure module.
 */

variable "provider" {
  description = "Cloud provider to use (aws or azure)"
  type        = string
  validation {
    condition     = contains(["aws", "azure"], var.provider)
    error_message = "Provider must be either 'aws' or 'azure'."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "mineclifford"
}

variable "environment" {
  description = "Environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "server_names" {
  description = "List of server instance names to create"
  type        = list(string)
  default     = ["instance1"]
}

variable "instance_type" {
  description = "Instance type/size for the server"
  type        = string
  default     = "t2.small"  # Default for AWS, will be translated for Azure
}

variable "region" {
  description = "AWS region or Azure location"
  type        = string
  default     = "us-east-2"  # AWS default, will be translated for Azure
}

variable "ssh_keys_path" {
  description = "Path to save generated SSH keys"
  type        = string
  default     = "../../ssh_keys"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC/VNET"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "username" {
  description = "Username for SSH access to instances"
  type        = string
  default     = "ubuntu"
}

variable "inventory_path" {
  description = "Path to save the Ansible inventory file"
  type        = string
  default     = "../../static_ip.ini"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# AWS-specific variables with empty defaults for Azure
# These will be ignored when using Azure

# Azure-specific variables with empty defaults for AWS
# These will be ignored when using AWS

variable "resource_group_name" {
  description = "Azure resource group name (ignored for AWS)"
  type        = string
  default     = "mineclifford"
}

variable "subscription_id" {
  description = "Azure subscription ID (ignored for AWS)"
  type        = string
  default     = ""
}