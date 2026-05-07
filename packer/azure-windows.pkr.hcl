###############################################################################
# Azure Golden Image — Windows Server 2022 with CIS Hardening
# Builder: azure-arm
# Output : Managed Image in the configured resource group
###############################################################################

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.0.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "client_id"       { type = string }
variable "client_secret"   { type = string  sensitive = true }
variable "tenant_id"       { type = string }
variable "subscription_id" { type = string }

variable "location" {
  type    = string
  default = "East US"
}

variable "resource_group" {
  type    = string
  default = "rg-golden-images"
}

variable "image_name_prefix" {
  type    = string
  default = "golden-win2022"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

# ---------------------------------------------------------------------------
# Source — Windows Server 2022 Datacenter (Azure marketplace)
# ---------------------------------------------------------------------------
source "azure-arm" "win2022" {
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  os_type         = "Windows"
  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2022-datacenter-g2"
  image_version   = "latest"

  location = var.location
  vm_size  = var.vm_size

  managed_image_resource_group_name = var.resource_group
  managed_image_name                = "${var.image_name_prefix}-{{timestamp}}"

  # ---- WinRM connection ----
  communicator   = "winrm"
  winrm_username = "packer"
  winrm_insecure = true
  winrm_use_ssl  = true

  # The Azure builder handles sysprep automatically when these are set
  os_disk_size_gb = 128

  azure_tags = {
    OS          = "WindowsServer2022"
    Hardening   = "CIS"
    BuiltBy     = "Packer"
    Environment = "production"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build {
  name    = "win2022-azure"
  sources = ["source.azure-arm.win2022"]

  provisioner "powershell" {
    scripts = ["../scripts/windows/install-updates.ps1"]
  }

  provisioner "powershell" {
    scripts = ["../scripts/windows/cis-harden.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["CLOUD=azure"]
    scripts          = ["../scripts/windows/install-agents.ps1"]
  }

  # Azure-specific generalize step (the builder triggers sysprep itself,
  # but we still flush logs / clear caches first).
  provisioner "powershell" {
    inline = [
      "Write-Host 'Final cleanup before Azure-managed sysprep'",
      "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\\Windows\\Temp\\*",
      "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\\Users\\packer\\AppData\\Local\\Temp\\*",
      "Clear-EventLog -LogName Application,System,Security -ErrorAction SilentlyContinue",
      "# Azure builder handles sysprep & generalize automatically — do NOT run it here"
    ]
  }

  post-processor "manifest" {
    output     = "manifest-azure-windows.json"
    strip_path = true
  }
}
