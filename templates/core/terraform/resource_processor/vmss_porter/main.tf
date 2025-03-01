data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}

data "template_file" "cloudconfig" {
  template = file("${path.module}/cloud-config.yaml")
  vars = {
    docker_registry_server                           = var.docker_registry_server
    terraform_state_container_name                   = var.terraform_state_container_name
    mgmt_resource_group_name                         = var.mgmt_resource_group_name
    mgmt_storage_account_name                        = var.mgmt_storage_account_name
    service_bus_deployment_status_update_queue       = var.service_bus_deployment_status_update_queue
    service_bus_resource_request_queue               = var.service_bus_resource_request_queue
    service_bus_namespace                            = "sb-${var.tre_id}.servicebus.windows.net"
    vmss_msi_id                                      = azurerm_user_assigned_identity.vmss_msi.client_id
    arm_subscription_id                              = data.azurerm_subscription.current.subscription_id
    arm_tenant_id                                    = data.azurerm_client_config.current.tenant_id
    resource_processor_vmss_porter_image_repository  = var.resource_processor_vmss_porter_image_repository
    resource_processor_vmss_porter_image_tag         = local.version
    app_insights_connection_string                   = var.app_insights_connection_string
    resource_processor_number_processes_per_instance = var.resource_processor_number_processes_per_instance
    key_vault_name                                   = var.key_vault_name
  }
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = data.template_file.cloudconfig.rendered
  }
}

resource "random_password" "password" {
  length           = 16
  lower            = true
  min_lower        = 1
  upper            = true
  min_upper        = 1
  number           = true
  min_numeric      = 1
  special          = true
  min_special      = 1
  override_special = "_%@"
}

resource "azurerm_key_vault_secret" "resource_processor_vmss_password" {
  name         = "resource-processor-vmss-password"
  value        = random_password.password.result
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "azurerm_user_assigned_identity" "vmss_msi" {
  name                = "id-vmss-${var.tre_id}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tre_core_tags
  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_linux_virtual_machine_scale_set" "vm_linux" {
  name                            = "vmss-rp-porter-${var.tre_id}"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  sku                             = "Standard_B2s"
  instances                       = 1
  admin_username                  = "adminuser"
  disable_password_authentication = false
  admin_password                  = random_password.password.result
  custom_data                     = data.template_cloudinit_config.config.rendered
  encryption_at_host_enabled      = false
  upgrade_mode                    = "Automatic"
  tags                            = local.tre_core_tags

  extension {
    auto_upgrade_minor_version = false
    automatic_upgrade_enabled  = false
    name                       = "healthRepairExtension"
    provision_after_extensions = []
    publisher                  = "Microsoft.ManagedServices"
    settings = jsonencode(
      {
        port        = 8080
        protocol    = "http"
        requestPath = "/health"
      }
    )
    type                 = "ApplicationHealthLinux"
    type_handler_version = "1.0"
  }

  automatic_os_upgrade_policy {
    disable_automatic_rollback  = false
    enable_automatic_os_upgrade = true
  }

  rolling_upgrade_policy {
    max_batch_instance_percent              = 100
    max_unhealthy_instance_percent          = 100
    max_unhealthy_upgraded_instance_percent = 100
    pause_time_between_batches              = "PT1M"

  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vmss_msi.id]
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic1"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = var.resource_processor_subnet_id
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# CustomData (e.g. image tag to run) changes will only take affect after vmss instances are reimaged.
# https://docs.microsoft.com/en-us/azure/virtual-machines/custom-data#can-i-update-custom-data-after-the-vm-has-been-created
resource "null_resource" "vm_linux_reimage" {
  provisioner "local-exec" {
    command = "az vmss reimage --name ${azurerm_linux_virtual_machine_scale_set.vm_linux.name} --resource-group ${var.resource_group_name}"
  }

  triggers = {
    # although we mainly want to catch image tag changes, this covers any custom data change.
    custom_data_hash = sha256(data.template_cloudinit_config.config.rendered)
  }

  depends_on = [
    azurerm_linux_virtual_machine_scale_set.vm_linux
  ]
}

resource "azurerm_role_assignment" "vmss_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.vmss_msi.principal_id
}

resource "azurerm_role_assignment" "vmss_sb_sender" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.vmss_msi.principal_id
}

resource "azurerm_role_assignment" "vmss_sb_receiver" {
  scope                = var.service_bus_namespace_id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.vmss_msi.principal_id
}

resource "azurerm_role_assignment" "subscription_administrator" {
  # Below is a workaround TF replacing this resource when using the data object.
  scope                = var.subscription_id != "" ? "/subscriptions/${var.subscription_id}" : data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_user_assigned_identity.vmss_msi.principal_id
}

resource "azurerm_role_assignment" "subscription_contributor" {
  # Below is a workaround TF replacing this resource when using the data object.
  scope                = var.subscription_id != "" ? "/subscriptions/${var.subscription_id}" : data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.vmss_msi.principal_id
}

resource "azurerm_key_vault_access_policy" "resource_processor" {
  key_vault_id = data.azurerm_key_vault.kv.id
  tenant_id    = azurerm_user_assigned_identity.vmss_msi.tenant_id
  object_id    = azurerm_user_assigned_identity.vmss_msi.principal_id

  secret_permissions      = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  certificate_permissions = ["Get", "Recover", "Import", "Delete", "Purge"]
}
