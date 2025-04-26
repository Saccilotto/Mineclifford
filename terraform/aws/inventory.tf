locals {
  instance_public_ips = { for name, instance in aws_instance.instance : name => aws_eip.eip[name].public_ip }
}

module "inventory" {
  source           = "../modules/common/inventory"
  instance_details = local.instance_public_ips
  ssh_user         = var.username
  inventory_path   = "${path.module}/../../static_ip.ini"
}