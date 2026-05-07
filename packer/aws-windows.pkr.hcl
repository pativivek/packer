###############################################################################
# AWS Golden Image — Windows Server 2022 with CIS Hardening
# Builder: amazon-ebs
# Output : Encrypted AMI in the configured region
#
# Notes on Windows builds:
#   * Communication is via WinRM, not SSH.
#   * The user-data script enables WinRM on first boot so Packer can connect.
#   * Sysprep is run at the end so each launched instance gets a fresh SID.
###############################################################################

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large" # Windows wants a bit more headroom than Linux
}

variable "image_name_prefix" {
  type    = string
  default = "golden-win2022"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# Source — Latest Windows Server 2022 English AMI from Amazon
# ---------------------------------------------------------------------------
source "amazon-ebs" "win2022" {
  region        = var.aws_region
  instance_type = var.instance_type

  source_ami_filter {
    filters = {
      name                = "Windows_Server-2022-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ami_name        = "${var.image_name_prefix}-{{timestamp}}"
  ami_description = "Golden Windows Server 2022 image, CIS-hardened, built by Packer"

  encrypt_boot                = true
  associate_public_ip_address = true

  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  # ---- WinRM connection (replaces SSH for Windows) ----
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_insecure = true
  winrm_use_ssl  = true
  winrm_timeout  = "20m"

  # user_data_file enables WinRM on first boot
  user_data_file = "../scripts/windows/bootstrap-winrm.ps1"

  tags = {
    Name        = "${var.image_name_prefix}-{{timestamp}}"
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
  name    = "win2022-aws"
  sources = ["source.amazon-ebs.win2022"]

  # 1. Apply Windows updates (long-running but essential)
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = build.Password
    scripts           = ["../scripts/windows/install-updates.ps1"]
  }

  # 2. CIS hardening
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = build.Password
    scripts           = ["../scripts/windows/cis-harden.ps1"]
  }

  # 3. Common agents (SSM, CloudWatch)
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = build.Password
    environment_vars  = ["CLOUD=aws"]
    scripts           = ["../scripts/windows/install-agents.ps1"]
  }

  # 4. Sysprep + shutdown — must be the LAST provisioner
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = build.Password
    scripts           = ["../scripts/windows/cleanup-sysprep.ps1"]
  }

  post-processor "manifest" {
    output     = "manifest-aws-windows.json"
    strip_path = true
  }
}
