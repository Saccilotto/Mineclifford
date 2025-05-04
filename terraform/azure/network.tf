module "security_rules" {
  source = "../modules/common/security-rules"
  environment_name = var.resource_group_name
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  address_space       = var.address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.common_tags

  depends_on = [azurerm_resource_group.rg]
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_prefixes

  # Ensure subnets are deleted first
  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_public_ip" "public_ip" {
  for_each            = toset(var.server_names)
  name                = "mineclifford-public-ip-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = {
    Name = "${var.resource_group_name}-public-ip-${each.key}"
  }
}
resource "azurerm_network_interface" "nic" {
  for_each            = toset(var.server_names)
  name                = "mineclifford-nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip[each.key].id
  }

  tags = merge (
    local.common_tags,
    {
      Name = "${var.resource_group_name}-nic-${each.key}"
    }
  )
  
  lifecycle {
    create_before_destroy = true
  }
}

# Associate NSG with NICs
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  for_each                  = azurerm_network_interface.nic
  network_interface_id      = each.value.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${module.security_rules.environment_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Dynamically create TCP security rules
  dynamic "security_rule" {
    for_each = module.security_rules.tcp_rules_with_priority
    content {
      name                       = "allow-${security_rule.value.name}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  # Dynamically create UDP security rules
  dynamic "security_rule" {
    for_each = module.security_rules.udp_rules_with_priority
    content {
      name                       = "allow-${security_rule.value.name}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
  
  security_rule {
    name                       = "allow-all-outbound"
    priority                   = 500  
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags  

  # Prevent "operation still running" errors
  timeouts {
    create = "30m"
    delete = "30m"
  }
}