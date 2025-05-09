provider "aws" {
  region = var.region
}

resource "aws_vpc" "minecraft_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "minecraft-vpc"
  }
}

resource "aws_subnet" "minecraft_subnet" {
  vpc_id                  = aws_vpc.minecraft_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags = {
    Name = "minecraft-subnet"
  }
}

resource "aws_internet_gateway" "minecraft_igw" {
  vpc_id = aws_vpc.minecraft_vpc.id
  tags = {
    Name = "minecraft-igw"
  }
}

resource "aws_route_table" "minecraft_route_table" {
  vpc_id = aws_vpc.minecraft_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft_igw.id
  }
  tags = {
    Name = "minecraft-route-table"
  }
}

resource "aws_route_table_association" "minecraft_rta" {
  subnet_id      = aws_subnet.minecraft_subnet.id
  route_table_id = aws_route_table.minecraft_route_table.id
}

resource "aws_security_group" "minecraft_sg" {
  name        = "minecraft-sg"
  description = "Allow Minecraft and SSH traffic"
  vpc_id      = aws_vpc.minecraft_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Minecraft server
  ingress {
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-sg"
  }
}

resource "tls_private_key" "minecraft_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "minecraft_keypair" {
  key_name   = "minecraft-keypair"
  public_key = tls_private_key.minecraft_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.minecraft_key.private_key_pem
  filename        = "minecraft_key.pem"
  file_permission = "0400"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "minecraft_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.minecraft_keypair.key_name
  subnet_id              = aws_subnet.minecraft_subnet.id
  vpc_security_group_ids = [aws_security_group.minecraft_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }

  tags = {
    Name = "minecraft-server"
  }

  # Generate inventory file for Ansible
  provisioner "local-exec" {
    command = <<-EOT
      cat > inventory.ini <<EOF
      [minecraft]
      ${self.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=minecraft_key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
      EOF
    EOT
  }
}