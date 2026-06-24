resource "azurerm_resource_group" "cdn" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.azure_location
}

resource "azurerm_storage_account" "origin" {
  name                            = replace("${var.project_name}${var.environment}", "-", "")
  resource_group_name             = azurerm_resource_group.cdn.name
  location                        = azurerm_resource_group.cdn.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  allow_nested_items_to_be_public = true
}

resource "azurerm_storage_container" "cdn" {
  name                  = "cdn-assets"
  storage_account_name  = azurerm_storage_account.origin.name
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "index" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.origin.name
  storage_container_name = azurerm_storage_container.cdn.name
  type                   = "Block"
  content_type           = "text/html"
  source_content         = "<html><body><h1>Failover Origin (Azure Blob Storage)</h1></body></html>"
}
