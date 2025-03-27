variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "odoo-project-rg"
}

variable "location" {
  description = "Azure region to deploy resources"
  default     = "eastus"
}

variable "admin_username" {
  description = "Username for the VM"
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key"
  default     = "C:/Users/JASDEV/.ssh/id_rsa.pub"
}