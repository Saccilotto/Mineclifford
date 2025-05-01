/**
 * # Azure Implementation for Minecraft Server Module
 *
 * This file defines the Azure-specific resources for the Minecraft server infrastructure.
 * It is used by the provider-agnostic main module when Azure is selected as the provider.
 */

variable "azure_location" {
  description = "Azure location for resources"
  type        = string
  default     = "East US 2"
}

variable "azure_resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "mineclifford"
}

variable "azure_vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s"
}

variable "azure_address_space" {
  description = "Address space for the Azure virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "azure_subnet_prefixes" {
  description = "Address prefixes for the Azure subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = ""
}

# Define Azure provider if using Azure
provider "azurerm" {
  features {}
  subscription_id = local.is_azure ? var.azure_subscription_id : null
}

# Create Azure Resource Group
resource "azurerm_resource_group" "rg" {
  count    = local.is_azure ? 1 : 0
  name     = var.azure_resource_group_name
  location = var.azure_location

  tags = local.common_tags
  
  timeouts {
    create = "60m"
    delete = "60m"
  }
}

# Create Azure Virtual Network
resource "azurerm_virtual_network" "vnet" {
  count               = local.is_azure ? 1 : 0
  name                = "${var.project_name}-vnet"
  address_space       = var.azure_address_space
  location            = azurerm_resource_group.rg[0].location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.common_tags

  depends_on = [azurerm_resource_group.rg]
}

# Create Azure Subnet
resource "azurerm_subnet" "subnet" {
  count                = local.is_azure ? 1 : 0
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.rg[0].name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = var.azure_subnet_prefixes

  # Service endpoints for enhanced security
  service_endpoints = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]

  lifecycle {
    create_before_destroy = true
  }
}

# Create Azure Public IPs
resource "azurerm_public_ip" "public_ip" {
  for_each            = local.is_azure ? toset(var.server_names) : []
  name                = "${var.project_name}-public-ip-${each.key}"
  location            = azurerm_resource_group.rg[0].location
  resource_group_name = azurerm_resource_group.rg[0].name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-public-ip-${each.key}"
    }
  )

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Azure-specific outputs
output "azure_resource_group_name" {
  description = "Azure Resource Group name"
  value       = local.is_azure ? azurerm_resource_group.rg[0].name : null
}

output "azure_vnet_name" {
  description = "Azure VNet name"
  value       = local.is_azure ? azurerm_virtual_network.vnet[0].name : null
}

output "azure_subnet_id" {
  description = "Azure Subnet ID"
  value       = local.is_azure ? azurerm_subnet.subnet[0].id : null
}

output "azure_vm_public_ips" {
  description = "Map of VM names to their public IPs"
  value       = local.is_azure ? { for name, vm in azurerm_linux_virtual_machine.vm : name => vm.public_ip_address } : {}
}

# Create Azure Network Interfaces
resource "azurerm_network_interface" "nic" {
  for_each            = local.is_azure ? toset(var.server_names) : []
  name                = "${var.project_name}-nic-${each.key}"
  location            = azurerm_resource_group.rg[0].location
  resource_group_name = azurerm_resource_group.rg[0].name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[each.key].id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-nic-${each.key}"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Create Azure Network Security Group
resource "azurerm_network_security_group" "nsg" {
  count               = local.is_azure ? 1 : 0
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.rg[0].location
  resource_group_name = azurerm_resource_group.rg[0].name

  # SSH
  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Minecraft Java
  security_rule {
    name                       = "allow-minecraft-java"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "25565"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Minecraft Bedrock
  security_rule {
    name                       = "allow-minecraft-bedrock"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "19132"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTP
  security_rule {
    name                       = "allow-http"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTPS
  security_rule {
    name                       = "allow-https"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Allow all outbound
  security_rule {
    name                       = "allow-all-outbound"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Associate NSG with NICs
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  for_each                  = local.is_azure ? toset(var.server_names) : []
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[0].id
}

# Create Azure Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  for_each            = local.is_azure ? toset(var.server_names) : []
  name                = "${var.project_name}-vm-${each.key}"
  location            = azurerm_resource_group.rg[0].location
  resource_group_name = azurerm_resource_group.rg[0].name
  
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  size               = var.azure_vm_size
  admin_username     = var.username
  disable_password_authentication = true

  tags = merge(
    local.common_tags,
    {
      Name = each.key
    }
  )

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
    disk_size_gb         = 64
  }
}