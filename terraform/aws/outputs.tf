# Output the public IPs of the instances
output "instance_public_ips" {
  value = local.instance_public_ips
}

# Output the SSH private keys (marked as sensitive)
output "instance_ssh_private_keys" {
  value     = module.ssh_keys.private_keys
  sensitive = true
}