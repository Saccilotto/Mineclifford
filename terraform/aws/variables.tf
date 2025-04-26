variable "project_name" {
  default = "mineclifford"
}

variable "region" {
  default = "us-east-2"
}

variable "vpc_name" {
  default = "mineclifford-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default = "10.0.0.0/16"
}

variable "subnet_name" {
  type    = string
  default = "mineclifford-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  default = "10.0.1.0/24"
}

variable "public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "vm_names" {
  default = ["instance1"]
}

variable "username" {
  default = "ubuntu"
}

variable "instance_type" {
  default = "t2.small"  
}