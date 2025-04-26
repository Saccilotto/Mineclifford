provider "azurerm" {
  subscription_id = var.azure_subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}