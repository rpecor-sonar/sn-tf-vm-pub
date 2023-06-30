terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.59.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  naming = "${var.projectName}-${var.env}"
  tags = {
    owner       = var.owner
    team        = var.team
    environment = var.env
  }
}

data "azurerm_resource_group" "services-rg" {
  name = "rg-services-01"
}

# Create virtual network
resource "azurerm_virtual_network" "core-vnet" {
  name                = "${local.naming}-vnet"
  address_space       = ["10.0.0.0/26"]
  location            = var.location
  resource_group_name = data.azurerm_resource_group.services-rg.name
}

# Create subnet
resource "azurerm_subnet" "subnet_one" {
  name                 = "${local.naming}-subnet1"
  resource_group_name  = data.azurerm_resource_group.services-rg.name
  virtual_network_name = azurerm_virtual_network.core-vnet.name
  address_prefixes     = ["10.0.0.0/28"]
}

# Create public IPs
resource "azurerm_public_ip" "windows_ip" {
  name                = "${local.naming}-pip"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.services-rg.name
  allocation_method   = "Dynamic"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "sn_tf_nsg" {
  name                = "${local.naming}-nsg"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.services-rg.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "sn_tf_nic" {
  name                = "${local.naming}-nic"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.services-rg.name

  ip_configuration {
    name                          = "${local.naming}-nic-ip"
    subnet_id                     = azurerm_subnet.subnet_one.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "sn_tf_nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.sn_tf_nic.id
  network_security_group_id = azurerm_network_security_group.sn_tf_nsg.id
}

resource "azurerm_windows_virtual_machine" "sn_tf_vm" {
  name                = "${local.naming}-win-vm"
  resource_group_name = data.azurerm_resource_group.services-rg.name
  location            = var.location
  size                = "Standard_D2s_v3"
  admin_username      = "adminuser"
  admin_password      = var.admin_pw
  network_interface_ids = [
    azurerm_network_interface.sn_tf_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-21h2-pro"
    version   = "latest"
  }
}

resource "azurerm_postgresql_server" "example" {
  name                = "${local.naming}-pgsql"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.services-rg.name

  administrator_login          = "pgsqladminuser"
  administrator_login_password = var.admin_pw

  sku_name   = "GP_Gen5_2"
  version    = "11"
  storage_mb = 640000

  backup_retention_days        = 7
  geo_redundant_backup_enabled = true
  auto_grow_enabled            = true

  #public_network_access_enabled    = false
  ssl_enforcement_enabled          = true
  #ssl_minimal_tls_version_enforced = "TLS1_2"
}