variable "instance_details" {
  description = "Map of instance names to their public IPs"
  type        = map(string)
}

variable "ssh_user" {
  description = "SSH username to access instances"
  type        = string
  default     = "ubuntu"
}

variable "inventory_path" {
  description = "Path where the inventory file should be created"
  type        = string
  default     = "../../inventory.ini"
}

locals {
  inventory_content = join("\n\n", [
    for name, ip in var.instance_details : "[${name}]\n${ip} ansible_ssh_user=${var.ssh_user} ansible_ssh_private_key_file=../../ssh_keys/${name}.pem"
  ])
}

# Create the inventory file
resource "local_file" "ansible_inventory" {
  content  = local.inventory_content
  filename = var.inventory_path
}

output "inventory_content" {
  value = local.inventory_content
}