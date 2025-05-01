/**
 * # AWS Implementation for Minecraft Server Module
 *
 * This file defines the AWS-specific resources for the Minecraft server infrastructure.
 * It is used by the provider-agnostic main module when AWS is selected as the provider.
 */

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-2"
}

variable "aws_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.small"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Define AWS provider if using AWS
provider "aws" {
  region = local.is_aws ? var.aws_region : null
}

# Create AWS VPC
resource "aws_vpc" "vpc" {
  count                = local.is_aws ? 1 : 0
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Create AWS Subnet
resource "aws_subnet" "subnet" {
  count                   = local.is_aws ? 1 : 0
  vpc_id                  = aws_vpc.vpc[0].id
  cidr_block              = var.aws_subnet_cidr
  map_public_ip_on_launch = true
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-subnet"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  count  = local.is_aws ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )

  depends_on = [aws_vpc.vpc]
}

# Create Route Table
resource "aws_route_table" "rt" {
  count  = local.is_aws ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-rt"
    }
  )
  
  depends_on = [aws_vpc.vpc, aws_internet_gateway.igw]
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "rta" {
  count          = local.is_aws ? 1 : 0
  subnet_id      = aws_subnet.subnet[0].id
  route_table_id = aws_route_table.rt[0].id
}

# Create Elastic IPs
resource "aws_eip" "eip" {
  for_each = local.is_aws ? toset(var.server_names) : []
  domain   = "vpc"
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-eip-${each.key}"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Create Security Group
resource "aws_security_group" "sg" {
  count       = local.is_aws ? 1 : 0
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name} project"
  vpc_id      = aws_vpc.vpc[0].id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Minecraft Java
  ingress {
    description = "Minecraft Java"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Minecraft Bedrock
  ingress {
    description = "Minecraft Bedrock"
    from_port   = 19132
    to_port     = 19132
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-sg"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Create key pairs from SSH keys
resource "aws_key_pair" "key_pair" {
  for_each   = local.is_aws ? module.ssh_keys.public_keys : {}
  key_name   = "${each.key}-key"
  public_key = each.value
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  count       = local.is_aws ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Create EC2 instances
resource "aws_instance" "instance" {
  for_each      = local.is_aws ? toset(var.server_names) : []
  ami           = data.aws_ami.ubuntu[0].id
  instance_type = var.aws_instance_type
  subnet_id     = aws_subnet.subnet[0].id
  
  key_name               = aws_key_pair.key_pair[each.key].key_name
  vpc_security_group_ids = [aws_security_group.sg[0].id]
  
  root_block_device {
    volume_size = 64
    volume_type = "gp2"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = each.key
    }
  )

  lifecycle {
    create_before_destroy = true
  }
  
  disable_api_termination = false
}

# Associate Elastic IPs with instances
resource "aws_eip_association" "eip_assoc" {
  for_each      = local.is_aws ? toset(var.server_names) : []
  instance_id   = aws_instance.instance[each.key].id
  allocation_id = aws_eip.eip[each.key].id
}

# AWS-specific outputs
output "aws_vpc_id" {
  description = "AWS VPC ID"
  value       = local.is_aws ? aws_vpc.vpc[0].id : null
}

output "aws_subnet_id" {
  description = "AWS Subnet ID"
  value       = local.is_aws ? aws_subnet.subnet[0].id : null
}

output "aws_security_group_id" {
  description = "AWS Security Group ID"
  value       = local.is_aws ? aws_security_group.sg[0].id : null
}

output "aws_instance_public_ips" {
  description = "Map of instance names to their public IPs"
  value       = local.is_aws ? { for name, instance in aws_instance.instance : name => aws_eip.eip[name].public_ip } : {}
}