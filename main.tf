terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "1ba8e0e2-0148-4cf3-9554-8fc1c2ba617d"
}

###############################
# Resource Group & Networking #
###############################

resource "azurerm_resource_group" "odoo_dev_rg" {
  name     = "odoo_dev_rg"
  location = "West US"
}

resource "azurerm_virtual_network" "odoo_dev_vnet" {
  name                = "odoo_dev_vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
}

# Subnet for PostgreSQL Flexible Server
resource "azurerm_subnet" "odoo_dev_db_subnet" {
  name                 = "odoo_dev_db_subnet"
  resource_group_name  = azurerm_resource_group.odoo_dev_rg.name
  virtual_network_name = azurerm_virtual_network.odoo_dev_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "postgresqlDelegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

# General subnet for other resources (e.g. VM NIC)
resource "azurerm_subnet" "odoo_dev_subnet" {
  name                 = "odoo_dev_subnet"
  resource_group_name  = azurerm_resource_group.odoo_dev_rg.name
  virtual_network_name = azurerm_virtual_network.odoo_dev_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

#########################
# Network Interfaces    #
#########################

# NIC for manually deployed VM (attach a public IP if desired)
resource "azurerm_network_interface" "odoo_dev_nic" {
  name                = "odoo_dev_nic"
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name

  ip_configuration {
    name                          = "odoo_dev_nic_ip"
    subnet_id                     = azurerm_subnet.odoo_dev_subnet.id
    private_ip_address_allocation = "Dynamic"
    # Optionally add public_ip_address_id if needed:
    # public_ip_address_id = azurerm_public_ip.odoo_dev_vm_pip.id
  }
}

#########################
# Network Security Group#
#########################

resource "azurerm_network_security_group" "odoo_dev_nsg" {
  name                = "odoo_dev_nsg"
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name

  security_rule {
    name                       = "HTTP"
    priority                   = 1006
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1007
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ODOO_ACCESS"
    priority                   = 1008
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8069"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "POSTGRES"
    priority                   = 1009
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "OUTBOUND_FOR_ODOO"
    priority                   = 1010
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8069"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "odoo_dev_subnet_nsg_association" {
  subnet_id                 = azurerm_subnet.odoo_dev_subnet.id
  network_security_group_id = azurerm_network_security_group.odoo_dev_nsg.id
}

#################
# Public IPs    #
#################

# Public IP for manually deployed VM (if needed)
resource "azurerm_public_ip" "odoo_dev_vm_pip" {
  name                = "odoo_dev_vm_pip"
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public IP for the Load Balancer
resource "azurerm_public_ip" "odoo_dev_lb_pip" {
  name                = "odoo_dev_lb_pip"
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

#################
# Load Balancer #
#################

resource "azurerm_lb" "odoo_dev_lb" {
  name                = "odoo_dev_lb"
  location            = azurerm_resource_group.odoo_dev_rg.location
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "odoo_dev_lb_frontip"
    public_ip_address_id = azurerm_public_ip.odoo_dev_lb_pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "odoo_dev_bap" {
  name            = "odoo_dev_bap"
  loadbalancer_id = azurerm_lb.odoo_dev_lb.id
}

resource "azurerm_lb_probe" "odoo_dev_lb_probe" {
  name                = "odoo_dev_lb_probe"
  loadbalancer_id     = azurerm_lb.odoo_dev_lb.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_outbound_rule" "odoo_dev_outbound_rule" {
  name                    = "odoo_dev_outbound_rule"
  loadbalancer_id         = azurerm_lb.odoo_dev_lb.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.odoo_dev_bap.id

  frontend_ip_configuration {
    name = "odoo_dev_lb_frontip"
  }
}

resource "azurerm_lb_rule" "odoo_dev_frontend_http_rule" {
  name                           = "odoo_dev_frontend_http_rule"
  loadbalancer_id                = azurerm_lb.odoo_dev_lb.id
  protocol                       = "Tcp"
  frontend_port                  = 8069
  backend_port                   = 8069
  frontend_ip_configuration_name = "odoo_dev_lb_frontip"
  disable_outbound_snat          = true
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.odoo_dev_bap.id]
  probe_id                       = azurerm_lb_probe.odoo_dev_lb_probe.id
}

#################
# Optional VMSS #
#################

# If you wish to use a Virtual Machine Scale Set, you can uncomment and adjust the block below.
resource "azurerm_linux_virtual_machine_scale_set" "odoo_dev_vmss" {
  name                = "odoo_dev_vmss"  # resource name (internal Terraform reference) 
  computer_name_prefix = "odoo-dev-vmss" # explicit prefix (no underscores) for the VMs
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
  location            = azurerm_resource_group.odoo_dev_rg.location
  sku                 = "Standard_D2s_v3"
  instances           = 1
  admin_username      = "is214"
  admin_password      = "Jasdev123"
  disable_password_authentication = false

  custom_data = filebase64("infrastructure/linux_data.sh")

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "odoo_dev_vmss_nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.odoo_dev_subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.odoo_dev_bap.id]
    }
  }
}

#####################################
# PostgreSQL Flexible Server Deploy #
#####################################

resource "azurerm_postgresql_flexible_server" "odoo_dev_postgres_instance" {
  name                   = "odoo-dev-postgres"
  resource_group_name    = azurerm_resource_group.odoo_dev_rg.name
  location               = azurerm_resource_group.odoo_dev_rg.location
  version                = "12"
  delegated_subnet_id    = azurerm_subnet.odoo_dev_db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.odoo_dev_postgres_private_dns_zone.id
  administrator_login    = "is214"
  administrator_password = "Jasdev123"
  public_network_access_enabled =  false    # Disable public network access when using VNet integration
  # zone = "1"  # Uncomment and adjust if needed

  storage_mb   = 32768
  storage_tier = "P30"

  sku_name = "GP_Standard_D2s_v3"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "odoo_dev_postgres_firewall_rule" {
  server_id        = azurerm_postgresql_flexible_server.odoo_dev_postgres_instance.id
  name             = "allow_all"
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_private_dns_zone" "odoo_dev_postgres_private_dns_zone" {
  name                = "odoobchewy.postgres.database.azure.com"  # Standard domain for Azure Database for PostgreSQL
  resource_group_name = azurerm_resource_group.odoo_dev_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "odoo_dev_postgres_dns_vnet_link" {
  name                  = "odoo_dev_postgres_dns_vnet_link"
  private_dns_zone_name = azurerm_private_dns_zone.odoo_dev_postgres_private_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.odoo_dev_vnet.id
  resource_group_name   = azurerm_resource_group.odoo_dev_rg.name
}
