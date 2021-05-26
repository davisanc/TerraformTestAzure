resource "azurerm_app_service_plan" "example" {
  name                = "juiceshop-appserviceplan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    tier = "Standard"
    size = "S1"
  }
}
#just a comment for change
resource "azurerm_app_service" "example" {
  name                = "juiceshop-app-service"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.example.id

  site_config {
    linux_fx_version = "DOCKER|${var.docker_image}:${var.docker_image_tag}"
    always_on = true
  }

  app_settings = {
    "DOCKER_REGISTRY_SERVER_URL" = "https://index.docker.io"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
  }
}