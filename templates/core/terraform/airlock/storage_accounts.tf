# 'External' storage account - drop location for import
resource "azurerm_storage_account" "sa_external_import" {
  name                     = local.import_external_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "GRS"

  # Don't allow anonymous access (unrelated to the 'public' networking rules)
  allow_blob_public_access = false

  # Important! we rely on the fact that the blob craeted events are issued when the creation of the blobs are done.
  # This is true ONLY when Hierarchical Namespace is DISABLED
  is_hns_enabled = false

  tags = {
    description = "airlock;import;external"
  }

  lifecycle { ignore_changes = [tags] }
}

# 'Approved' export
resource "azurerm_storage_account" "sa_export_approved" {
  name                     = local.export_approved_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "GRS"

  # Don't allow anonymous access (unrelated to the 'public' networking rules)
  allow_blob_public_access = false

  # Important! we rely on the fact that the blob craeted events are issued when the creation of the blobs are done.
  # This is true ONLY when Hierarchical Namespace is DISABLED
  is_hns_enabled = false

  tags = {
    description = "airlock;export;approved"
  }

  lifecycle { ignore_changes = [tags] }
}

# 'In-Progress' storage account
resource "azurerm_storage_account" "sa_import_in_progress" {
  name                     = local.import_in_progress_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "GRS"
  allow_blob_public_access = false

  # Important! we rely on the fact that the blob craeted events are issued when the creation of the blobs are done.
  # This is true ONLY when Hierarchical Namespace is DISABLED
  is_hns_enabled = false

  tags = {
    description = "airlock;import;in-progress"
  }

  network_rules {
    default_action = var.enable_local_debugging ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  lifecycle { ignore_changes = [tags] }
}

data "azurerm_private_dns_zone" "blobcore" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_endpoint" "stg_ip_import_pe" {
  name                = "stg-ip-import-blob-${var.tre_id}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.shared_subnet_id

  lifecycle { ignore_changes = [tags] }

  private_dns_zone_group {
    name                 = "private-dns-zone-group-stg-import-ip"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blobcore.id]
  }

  private_service_connection {
    name                           = "psc-stgipimport-${var.tre_id}"
    private_connection_resource_id = azurerm_storage_account.sa_import_in_progress.id
    is_manual_connection           = false
    subresource_names              = ["Blob"]
  }
}


# 'Rejected' storage account
resource "azurerm_storage_account" "sa_import_rejected" {
  name                     = local.import_rejected_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "GRS"
  allow_blob_public_access = false

  # Important! we rely on the fact that the blob craeted events are issued when the creation of the blobs are done.
  # This is true ONLY when Hierarchical Namespace is DISABLED
  is_hns_enabled = false

  tags = {
    description = "airlock;import;rejected"
  }

  network_rules {
    default_action = var.enable_local_debugging ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_private_endpoint" "stgipimportpe" {
  name                = "stg-import-rej-blob-${var.tre_id}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.shared_subnet_id

  lifecycle { ignore_changes = [tags] }

  private_dns_zone_group {
    name                 = "private-dns-zone-group-stg-import-rej"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.blobcore.id]
  }

  private_service_connection {
    name                           = "psc-stg-import-rej-${var.tre_id}"
    private_connection_resource_id = azurerm_storage_account.sa_import_rejected.id
    is_manual_connection           = false
    subresource_names              = ["Blob"]
  }
}
