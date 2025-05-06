# Output the public IPs of the instances
output "instance_public_ips" {
  description = "Map of instance names to their public IPs"
  value = {
    for name, eip in aws_eip.eip : name => eip.public_ip
  }
}

# Output the SSH private keys (marked as sensitive)
output "instance_ssh_private_keys" {
  value     = module.ssh_keys.private_keys
  sensitive = true
}