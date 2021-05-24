data "azurerm_web_application_firewall_policy" "example" {
  resource_group_name = "existing"
  name                = "existing"
}

output "id" {
  value = data.azurerm_web_application_firewall_policy.example.id
}