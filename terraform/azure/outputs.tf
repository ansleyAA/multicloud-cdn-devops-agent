output "blob_endpoint" {
  description = "Use this as azure_blob_endpoint in the AWS module"
  value       = "${azurerm_storage_account.origin.name}.blob.core.windows.net"
}

output "container_name" {
  value = azurerm_storage_container.cdn.name
}

output "storage_account_name" {
  value = azurerm_storage_account.origin.name
}
