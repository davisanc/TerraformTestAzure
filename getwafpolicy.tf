data "azurerm_web_application_firewall_policy" "example" {
  resource_group_name = "WAF-DevOps-app"
  name                = "WAF-Devops-wafpolicy"
}

output "id" {
  value = data.azurerm_web_application_firewall_policy.example.id
}