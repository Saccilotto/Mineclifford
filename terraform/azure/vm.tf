module "ssh_keys" {
  source         = "../modules/common/ssh-keys"
  instance_names = var.server_names
  keys_path      = "${path.module}/../../ssh_keys"
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each            = toset(var.server_names)
  name                = each.key
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  size               = "Standard_B2s"
  admin_username     = var.username
  disable_password_authentication = true

  tags = local.common_tags

  timeouts {
    create = "60m"
    delete = "30m"
  }
  
  admin_ssh_key {
    username   = var.username
    public_key = module.ssh_keys.public_keys[each.key]
  }
 
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
    
  os_disk {
    storage_account_type = "Standard_LRS"
    name                 = "osdisk-${each.key}"
    caching              = "ReadWrite"
    disk_size_gb         =  64
  }
}