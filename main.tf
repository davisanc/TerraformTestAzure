terraform {
  backend "azurerm" {
    resource_group_name   = "WAF-DevOps"
    storage_account_name  = "wafdevopssa"
    container_name        = "tstate"
  }

  required_providers {
    azurerm = {
      # Specify what version of the provider we are going to utilise
      source = "hashicorp/azurerm"
      # version = ">= 2.4.1"
      version = "0.12.3"
    }
  }
}
provider "azurerm" {
  features {
      key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}
# Create our Resource Group - WAF-DevOps-RG
resource "azurerm_resource_group" "rg" {
  name     = "WAF-DevOps"
  location = "UK South"
}
# Create our Virtual Network - WAF-DevOps-VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "WAF-Devops-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
# Create our Subnet to hold our VM - Virtual Machines
resource "azurerm_subnet" "sn" {
  name                 = "VM"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes       = ["10.0.1.0/24"]
}
resource "azurerm_subnet" "app-gw-subnet" {
  name                 = "app-gw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_web_application_firewall_policy" "WAF-Devops-waf" {
  name                = "WAF-Devops-wafpolicy"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  custom_rules {
    name      = "Rule1"
    priority  = 1
    rule_type = "MatchRule"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["192.168.1.0/24", "10.0.0.0/24"]
    }

    action = "Block"
  }

  custom_rules {
    name      = "Rule2"
    priority  = 2
    rule_type = "MatchRule"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["192.168.1.0/24"]
    }

    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "UserAgent"
      }

      operator           = "Contains"
      negation_condition = false
      match_values       = ["Windows"]
    }

    action = "Block"
  }

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    exclusion {
      match_variable          = "RequestHeaderNames"
      selector                = "x-company-secret-header"
      selector_match_operator = "Equals"
    }
    exclusion {
      match_variable          = "RequestCookieNames"
      selector                = "too-tasty"
      selector_match_operator = "EndsWith"
    }

    managed_rule_set {
      type    = "OWASP"
      version = "3.1"
      rule_group_override {
        rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
        disabled_rules = [
          "920300",
          "920440"
        ]
      }
    }
  }

}


module "application-gateway" {
  source                    = "aztfm/application-gateway/azurerm"
  version                   = "1.0.0"
  name                      = "application-gateway"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  sku                       = { tier = "WAF_v2", size = "WAF_v2", capacity = 2 }
  subnet_id                 = azurerm_subnet.app-gw-subnet.id
  frontend_ip_configuration = { public_ip_address_id = azurerm_public_ip.pip.id, private_ip_address = "10.0.2.10", private_ip_address_allocation = "Static" }
  #firewall_policy_id = data.azurerm_web_application_firewall_policy.policyexample.id
  backend_address_pools = [
    { name = "backend-address-pool-1" },
    { name = "backend-address-pool-2", ip_addresses = "10.0.0.4,10.0.0.5,10.0.0.6" }
  ]
  http_listeners = [
    { name = "http-listener", frontend_ip_configuration = "Public", port = 80, protocol = "http" }
  ]
  backend_http_settings = [{ name = "backend-http-setting", port = 80, protocol = "http", request_timeout = 20 }]
  request_routing_rules = [
    {
      name                       = "request-routing-rule-1"
      http_listener_name         = "http-listener"
      backend_address_pool_name  = "backend-address-pool-1"
      backend_http_settings_name = "backend-http-setting"
    }
  ]
}

# Create our Azure Storage Account - WAF-DevOp-sa
resource "azurerm_storage_account" "wafdevopssa" {
  name                     = "wafdevopssa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    environment = "WAF-DevOps-tag-v2"
  }
}
# Create our vNIC for our VM and assign it to our Virtual Machines Subnet
resource "azurerm_network_interface" "vmnic" {
  name                = "WAF-DevOp-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
 
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sn.id
    private_ip_address_allocation = "Dynamic"
  }
}
# Create our Virtual Machine - WAF-DevOps-VM01
resource "azurerm_virtual_machine" "WAF-DevOp-vm01" {
  name                  = "WAF-DevOp-vm01"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vmnic.id]
  vm_size               = "Standard_B2s"
  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter-Server-Core-smalldisk"
    version   = "latest"
  }
  storage_os_disk {
    name              = "WAF-DevOpsvm01os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name      = "WAF-DevOpsvm01"
    admin_username     = "david"
    admin_password     = "Sanchez123$%"
  }
  os_profile_windows_config {
  }
}