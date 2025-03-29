output "odoo_dev_vm_public_ip" {
  value       = azurerm_public_ip.odoo_dev_vm_pip.ip_address
  description = "The public IP address for the manually deployed VM."
}
