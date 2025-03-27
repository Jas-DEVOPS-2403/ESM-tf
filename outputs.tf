output "odoo_public_ip_output" {
  value = azurerm_public_ip.odoo_public_ip.ip_address
  description = "The public IP address of the Odoo server"
}