variable "prefix" {
  description = "Prefix for all resources"
  type        = string
  default     = "mineclifford"
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US 2"
}

variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27.3"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "min_node_count" {
  description = "Minimum number of nodes in the AKS cluster"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes in the AKS cluster"
  type        = number
  default     = 3
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 80
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    Project     = "mineclifford"
    Environment = "production"
    ManagedBy   = "terraform"
    Owner       = "minecraft"
  }
}