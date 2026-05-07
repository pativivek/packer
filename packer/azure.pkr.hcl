###############################################################################
# Azure Golden Image — RHEL 9 with CIS Hardening
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
# Variables — typically supplied via env vars (PKR_VAR_*) or a tfvars-style file
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
  type        = string
  description = "Resource group where the managed image will be saved"
  default     = "rg-golden-images"
}

variable "image_name_prefix" {
  type    = string
  default = "golden-rhel9"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------
source "azure-arm" "rhel9" {
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  os_type         = "Linux"
  image_publisher = "RedHat"
  image_offer     = "RHEL"
  image_sku       = "9-lvm-gen2"
  image_version   = "latest"

  location = var.location
  vm_size  = var.vm_size

  managed_image_resource_group_name = var.resource_group
  managed_image_name                = "${var.image_name_prefix}-{{timestamp}}"

  azure_tags = {
    OS          = "RHEL9"
    Hardening   = "CIS"
    BuiltBy     = "Packer"
    Environment = "production"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build {
  name    = "rhel9-azure"
  sources = ["source.azure-arm.rhel9"]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait || true",
    ]
  }

  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/cis-harden.sh"]
  }

  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/install-agents.sh"]
    environment_vars = ["CLOUD=azure"]
  }

  # Azure requires a `deprovision` step at the very end
  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/cleanup.sh"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline_shebang  = "/bin/sh -x"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync",
    ]
  }

  post-processor "manifest" {
    output     = "manifest-azure.json"
    strip_path = true
  }
}
