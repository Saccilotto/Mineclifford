resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
  
  # Ensures that even if the operation fails initially, it will retry
  timeouts {
    create = "60m"
    delete = "60m"
  }
}
