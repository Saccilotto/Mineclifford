# Adjust the output to use the dynamically generated map
output "vm_public_ips" {
  value = local.vm_public_ips
}

output "vm_ssh_private_keys" {
  value     = module.ssh_keys.private_keys
  sensitive = true
}