###############################################################################
# GCP Golden Image — RHEL 9 with CIS Hardening
# Builder: googlecompute
# Output : Custom Image in the configured project
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
  description = "GCP project id where the image will be created"
}

variable "credentials_file" {
  type        = string
  description = "Path to the service account JSON. Leave empty when using ADC / OIDC."
  default     = ""
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "image_name_prefix" {
  type    = string
  default = "golden-rhel9"
}

variable "image_family" {
  type    = string
  default = "golden-rhel9"
}

# ---------------------------------------------------------------------------
# Source — RHEL 9 from rhel-cloud public images
# ---------------------------------------------------------------------------
source "googlecompute" "rhel9" {
  project_id = var.project_id

  # Only set credentials_file when explicitly provided; otherwise rely on
  # Application Default Credentials (gcloud auth or workload identity in CI).
  credentials_file = var.credentials_file != "" ? var.credentials_file : null

  source_image_family     = "rhel-9"
  source_image_project_id = ["rhel-cloud"]

  zone         = var.zone
  machine_type = var.machine_type
  ssh_username = "packer"

  image_name        = "${var.image_name_prefix}-{{timestamp}}"
  image_family      = var.image_family
  image_description = "Golden RHEL 9 image, CIS-hardened, built by Packer"

  image_labels = {
    os         = "rhel9"
    hardening  = "cis"
    built-by   = "packer"
    managed-by = "packer-golden-image"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build {
  name    = "rhel9-gcp"
  sources = ["source.googlecompute.rhel9"]

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
    environment_vars = ["CLOUD=gcp"]
  }

  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/cleanup.sh"]
  }

  post-processor "manifest" {
    output     = "manifest-gcp.json"
    strip_path = true
  }
}
