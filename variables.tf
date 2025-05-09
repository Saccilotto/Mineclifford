variable "region" {
  description = "AWS region"
  default     = "us-east-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.medium"
}

variable "minecraft_version" {
  description = "Minecraft server version"
  default     = "1.19.2"
}

variable "minecraft_memory" {
  description = "Memory allocated to Minecraft server"
  default     = "3G"
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