locals {
  vm_public_ips = { for name, vm in azurerm_linux_virtual_machine.vm : name => vm.public_ip_address }
}

module "inventory" {
  source           = "../modules/common/inventory"
  instance_details = local.vm_public_ips
  ssh_user         = var.username
  inventory_path   = "${path.module}/../../static_ip.ini"
}