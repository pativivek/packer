###############################################################################
# GCP Golden Image — Windows Server 2022 with CIS Hardening
# Builder: googlecompute
# Output : Custom Image in the configured project
#
# The googlecompute builder auto-creates a temporary Windows password and
# uses WinRM over HTTPS by default — no manual user-data needed.
###############################################################################

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.1.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCP project id"
}

variable "credentials_file" {
  type    = string
  default = ""
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "image_name_prefix" {
  type    = string
  default = "golden-win2022"
}

variable "image_family" {
  type    = string
  default = "golden-win2022"
}

# ---------------------------------------------------------------------------
# Source — Windows Server 2022 Datacenter from Google's public images
# ---------------------------------------------------------------------------
source "googlecompute" "win2022" {
  project_id = var.project_id

  credentials_file = var.credentials_file != "" ? var.credentials_file : null

  source_image_family     = "windows-2022"
  source_image_project_id = ["windows-cloud"]

  zone         = var.zone
  machine_type = var.machine_type
  disk_size    = 100

  # ---- WinRM connection ----
  communicator = "winrm"
  winrm_username = "packer_user"
  winrm_insecure = true
  winrm_use_ssl  = true

  # GCP-specific: tell the metadata server to enable WinRM
  metadata = {
    sysprep-specialize-script-cmd = "winrm quickconfig -quiet & winrm set winrm/config/service/auth @{Basic=\"true\"} & winrm set winrm/config/service @{AllowUnencrypted=\"true\"}"
  }

  image_name        = "${var.image_name_prefix}-{{timestamp}}"
  image_family      = var.image_family
  image_description = "Golden Windows Server 2022 image, CIS-hardened, built by Packer"

  image_labels = {
    os         = "windows-2022"
    hardening  = "cis"
    built-by   = "packer"
    managed-by = "packer-golden-image"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build {
  name    = "win2022-gcp"
  sources = ["source.googlecompute.win2022"]

  provisioner "powershell" {
    scripts = ["../scripts/windows/install-updates.ps1"]
  }

  provisioner "powershell" {
    scripts = ["../scripts/windows/cis-harden.ps1"]
  }

  provisioner "powershell" {
    environment_vars = ["CLOUD=gcp"]
    scripts          = ["../scripts/windows/install-agents.ps1"]
  }

  # GCP-specific cleanup. GCE Sysprep runs on first boot via specialize
  # script when GCESysprep is enabled, so we just clean up artefacts here.
  provisioner "powershell" {
    inline = [
      "Write-Host 'Final cleanup before GCE image capture'",
      "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\\Windows\\Temp\\*",
      "Clear-EventLog -LogName Application,System,Security -ErrorAction SilentlyContinue",
      "& GCESysprep -NoShutdown"
    ]
  }

  post-processor "manifest" {
    output     = "manifest-gcp-windows.json"
    strip_path = true
  }
}
