output "resource_group_name" {
  value = azurerm_resource_group.jmeter_rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.jmeter_storage.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.jmeter_storage.primary_access_key
  sensitive = true
}

output "storage_file_share_name" {
  value = azurerm_storage_share.jmeter_share.name
}

output "storage_file_share_url" {
  value = azurerm_storage_share.jmeter_share.url
}

output "jmeter_controller_name" {
  value = azurerm_container_group.jmeter_controller.name
}

output "jmeter_controller_ip" {
  value = azurerm_container_group.jmeter_controller.ip_address
}

output "jmeter_workers_names" {
  value = join(",", "${azurerm_container_group.jmeter_workers.*.name}")
}

output "jmeter_workers_ip_list" {
  value = ["${azurerm_container_group.jmeter_workers.*.ip_address}"]
}

output "jmeter_workers_ips" {
  value = join(",", "${azurerm_container_group.jmeter_workers.*.ip_address}")
}

output "jmeter_results_file" {
  value = var.JMETER_RESULTS_FILE
}

output "jmeter_dashboard_folder" {
  value = var.JMETER_DASHBOARD_FOLDER
}
