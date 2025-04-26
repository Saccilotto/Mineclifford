variable "instance_names" {
  description = "List of instance names to create SSH keys for"
  type        = list(string)
}

variable "keys_path" {
  description = "Path to save SSH key files"
  type        = string
  default     = "../../ssh_keys"
}

# Generate the SSH keys
resource "tls_private_key" "ssh_key" {
  for_each  = toset(var.instance_names)
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Save the private keys to files
resource "local_file" "ssh_key_files" {
  for_each        = tls_private_key.ssh_key
  content         = each.value.private_key_pem
  filename        = "${var.keys_path}/${each.key}.pem"
  file_permission = "0400"
}

# Output the generated keys
output "public_keys" {
  value = {
    for name, key in tls_private_key.ssh_key : name => key.public_key_openssh
  }
}

output "private_keys" {
  value     = {
    for name, key in tls_private_key.ssh_key : name => key.private_key_pem
  }
  sensitive = true
}

output "key_pairs" {
  value = tls_private_key.ssh_key
}