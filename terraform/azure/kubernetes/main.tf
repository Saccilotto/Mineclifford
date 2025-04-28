provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

resource "azurerm_resource_group" "minecraft" {
  name     = "${var.prefix}-rg"
  location = var.location

  tags = var.tags
}

resource "azurerm_virtual_network" "minecraft" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name
  address_space       = ["10.0.0.0/16"]

  tags = var.tags
}

resource "azurerm_subnet" "minecraft" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.minecraft.name
  virtual_network_name = azurerm_virtual_network.minecraft.name
  address_prefixes     = ["10.0.1.0/24"]

  # Required for AKS network plugin
  service_endpoints = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "minecraft" {
  name                = "${var.prefix}-workspace"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}

# Create AKS cluster
resource "azurerm_kubernetes_cluster" "minecraft" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name
  dns_prefix          = "${var.prefix}-k8s"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    vm_size             = var.vm_size
    node_count          = var.min_node_count
    max_count           = var.max_node_count
    min_count           = var.min_node_count
    os_disk_size_gb     = var.os_disk_size_gb
    vnet_subnet_id      = azurerm_subnet.minecraft.id
    node_labels = {
      nodepool = "default"
      app      = "minecraft"
    }
    tags = var.tags
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    network_policy    = "calico"
  }

  identity {
    type = "SystemAssigned"
  }

  # Monitor configuration using the monitor_metrics add-on
  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  tags = var.tags
}

# Connect Log Analytics to AKS
resource "azurerm_monitor_diagnostic_setting" "minecraft" {
  name                       = "${var.prefix}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.minecraft.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.minecraft.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
  }
}

# Create a Public IP Address for the Kubernetes Load Balancer
resource "azurerm_public_ip" "minecraft_java" {
  name                = "${var.prefix}-java-pubip"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_public_ip" "minecraft_bedrock" {
  name                = "${var.prefix}-bedrock-pubip"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Create Network Security Group for Minecraft ports
resource "azurerm_network_security_group" "minecraft" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.minecraft.location
  resource_group_name = azurerm_resource_group.minecraft.name

  security_rule {
    name                       = "AllowMinecraftJava"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "25565"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowMinecraftBedrock"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "19132"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Output the AKS cluster name and resource group name
output "kubernetes_cluster_name" {
  value = azurerm_kubernetes_cluster.minecraft.name
}

output "kubernetes_cluster_resource_group" {
  value = azurerm_resource_group.minecraft.name
}

# Output the AKS cluster kubeconfig
output "aks_kube_config" {
  value     = azurerm_kubernetes_cluster.minecraft.kube_config_raw
  sensitive = true
}

# Output public IP addresses
output "minecraft_java_ip" {
  value = azurerm_public_ip.minecraft_java.ip_address
}

output "minecraft_bedrock_ip" {
  value = azurerm_public_ip.minecraft_bedrock.ip_address
}