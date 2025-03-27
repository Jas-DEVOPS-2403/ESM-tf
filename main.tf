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

# Create a resource group
resource "azurerm_resource_group" "odoo_rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create a virtual network
resource "azurerm_virtual_network" "odoo_vnet" {
  name                = "odoo-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.odoo_rg.location
  resource_group_name = azurerm_resource_group.odoo_rg.name
}

# Create a subnet
resource "azurerm_subnet" "odoo_subnet" {
  name                 = "odoo-subnet"
  resource_group_name  = azurerm_resource_group.odoo_rg.name
  virtual_network_name = azurerm_virtual_network.odoo_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a public IP with static allocation
resource "azurerm_public_ip" "odoo_public_ip" {
  name                = "odoo-public-ip"
  location            = azurerm_resource_group.odoo_rg.location
  resource_group_name = azurerm_resource_group.odoo_rg.name
  allocation_method   = "Static"
}

# Create a network security group with rules for SSH, Odoo (8069) and standard HTTP (80)
resource "azurerm_network_security_group" "odoo_nsg" {
  name                = "odoo-nsg"
  location            = azurerm_resource_group.odoo_rg.location
  resource_group_name = azurerm_resource_group.odoo_rg.name

  # Allow SSH
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow Odoo web interface on port 8069
  security_rule {
    name                       = "HTTP-Odoo"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8069"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow standard HTTP on port 80
  security_rule {
    name                       = "HTTP-Standard"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a network interface and attach the public IP
resource "azurerm_network_interface" "odoo_nic" {
  name                = "odoo-nic"
  location            = azurerm_resource_group.odoo_rg.location
  resource_group_name = azurerm_resource_group.odoo_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.odoo_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.odoo_public_ip.id
  }
}

# Associate the NSG with the NIC
resource "azurerm_network_interface_security_group_association" "odoo_association" {
  network_interface_id      = azurerm_network_interface.odoo_nic.id
  network_security_group_id = azurerm_network_security_group.odoo_nsg.id
}

# Create the Linux virtual machine for Odoo
resource "azurerm_linux_virtual_machine" "odoo_vm" {
  name                = "odoo-vm"
  resource_group_name = azurerm_resource_group.odoo_rg.name
  location            = azurerm_resource_group.odoo_rg.location
  size                = "Standard_B2s"  # 2 vCPUs, 4 GB RAM - sufficient for small Odoo deployment
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.odoo_nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # This script installs Odoo 18 on the VM.
  # Note: Added Babel installation after the requirements installation.
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    # Update system
    sudo apt-get update
    sudo apt-get upgrade -y

    # Install dependencies
    sudo apt-get install -y git python3-pip build-essential wget python3-dev python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less postgresql postgresql-server-dev-all libpq-dev

    # Additional dependencies that may be required for Odoo 18
    sudo apt-get install -y npm
    sudo npm install -g rtlcss
    sudo apt-get install -y libsass-dev libxml2-dev libjpeg-dev zlib1g-dev libpng-dev

    # Create Odoo user
    sudo useradd -m -d /opt/odoo -U -r -s /bin/bash odoo

    # Install wkhtmltopdf for report generation
    sudo apt-get install -y wkhtmltopdf

    # Configure PostgreSQL for Odoo
    sudo -u postgres createuser -s odoo
    sudo -u postgres createdb odoo

    # Install Odoo 18
    sudo git clone --depth 1 --branch 18.0 https://www.github.com/odoo/odoo /opt/odoo/odoo
    sudo chown -R odoo:odoo /opt/odoo

    # Create and activate virtual environment for better dependency management
    sudo -u odoo mkdir -p /opt/odoo/venv
    sudo -u odoo python3 -m venv /opt/odoo/venv

    # Upgrade pip and install required Python packages in the virtual environment
    sudo -u odoo /opt/odoo/venv/bin/python3 -m pip install --upgrade pip
    sudo -u odoo /opt/odoo/venv/bin/python3 -m pip install wheel
    sudo -u odoo /opt/odoo/venv/bin/python3 -m pip install -r /opt/odoo/odoo/requirements.txt

    # Explicitly install additional dependencies that may be missing:
    sudo -u odoo /opt/odoo/venv/bin/python3 -m pip install Babel pytz urllib3

    # (Optional) Verify installations by listing installed packages
    sudo -u odoo /opt/odoo/venv/bin/pip freeze | grep -E 'Babel|pytz|urllib3'

    # Create Odoo config file
    sudo mkdir -p /etc/odoo
    sudo touch /etc/odoo/odoo.conf
    sudo chown odoo:odoo /etc/odoo/odoo.conf
    sudo chmod 640 /etc/odoo/odoo.conf

    sudo bash -c 'cat > /etc/odoo/odoo.conf << EOF
    [options]
    ; Admin password for creating, restoring and backing up databases
    admin_passwd = admin_password_change_me
    db_host = False
    db_port = False
    db_user = odoo
    db_password = False
    addons_path = /opt/odoo/odoo/addons
    logfile = /var/log/odoo/odoo.log
    EOF'

    # Create log directory
    sudo mkdir -p /var/log/odoo
    sudo chown odoo:odoo /var/log/odoo

    # Create systemd service file for Odoo
    sudo bash -c 'cat > /etc/systemd/system/odoo.service << EOF
    [Unit]
    Description=Odoo
    Requires=postgresql.service
    After=network.target postgresql.service

    [Service]
    Type=simple
    SyslogIdentifier=odoo
    PermissionsStartOnly=true
    User=odoo
    Group=odoo
    ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo/odoo.conf
    StandardOutput=journal+console

    [Install]
    WantedBy=multi-user.target
    EOF'

    # Start Odoo service
    sudo systemctl daemon-reload
    sudo systemctl enable odoo
    sudo systemctl start odoo

  EOF
  )
}

# Output the public IP for easy access
output "odoo_public_ip" {
  value       = azurerm_public_ip.odoo_public_ip.ip_address
  description = "The public IP address of the Odoo server"
}
