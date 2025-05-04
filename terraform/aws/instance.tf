module "ssh_keys" {
  source         = "../modules/common/ssh-keys"
  instance_names = var.server_names
  keys_path      = "${path.module}/../../ssh_keys"
}

# Create AWS key pairs from the module output
resource "aws_key_pair" "generated_key" {
  for_each   = toset(var.server_names)
  key_name   = "${each.key}-key-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  public_key = module.ssh_keys.public_keys[each.key]
} 

data "aws_ami" "ubuntu" {
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

# EC2 Instances
resource "aws_instance" "instance" {
  for_each      = toset(var.server_names)
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.subnet.id
  
  key_name               = aws_key_pair.generated_key[each.key].key_name
  vpc_security_group_ids = [aws_security_group.sg.id]
  
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

  # Faster and more reliable termination
  lifecycle {
    create_before_destroy = true
  }
  
  # Ensure termination protection is off
  disable_api_termination = false
}

# Associate Elastic IPs with instances
resource "aws_eip_association" "eip_assoc" {
  for_each       = toset(var.server_names)
  instance_id    = aws_instance.instance[each.key].id
  allocation_id  = aws_eip.eip[each.key].id
}