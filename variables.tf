variable "region" {
  description = "AWS region"
  default     = "sa-east-1"   // São Paulo, Brazil
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.medium"
}

variable "minecraft_version" {
  description = "Minecraft server version"
  default     = "1.22.5"
}

variable "minecraft_memory" {
  description = "Memory allocated to Minecraft server"
  default     = "4G"
}

variable "import_world" {
  description = "Path to world zip file to import"
  default     = ""
  type        = string
}

variable "force_version" {
  description = "Force specific Minecraft server version"
  default     = ""
  type        = string
}