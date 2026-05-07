###############################################################################
# AWS Golden Image — RHEL 9 with CIS Hardening
# Builder: amazon-ebs
# Output : Encrypted AMI in the configured region
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
# Variables (override via -var, -var-file, or env PKR_VAR_<name>)
# ---------------------------------------------------------------------------
variable "aws_region" {
  type        = string
  description = "AWS region to build the AMI in"
  default     = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "image_name_prefix" {
  type    = string
  default = "golden-rhel9"
}

variable "ssh_username" {
  type    = string
  default = "ec2-user"
}

variable "vpc_id" {
  type        = string
  description = "Optional VPC id; leave empty to use default VPC"
  default     = ""
}

variable "subnet_id" {
  type        = string
  description = "Optional subnet id; leave empty to let AWS pick"
  default     = ""
}

# ---------------------------------------------------------------------------
# Source — RHEL 9 from Red Hat (owner 309956199498)
# ---------------------------------------------------------------------------
source "amazon-ebs" "rhel9" {
  region        = var.aws_region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username

  # Always pick the latest official RHEL 9 image
  source_ami_filter {
    filters = {
      name                = "RHEL-9*_HVM-*x86_64*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["309956199498"] # Red Hat
    most_recent = true
  }

  ami_name        = "${var.image_name_prefix}-{{timestamp}}"
  ami_description = "Golden RHEL 9 image, CIS-hardened, built by Packer"

  # Encryption + sane defaults
  encrypt_boot = true

  # Optional VPC / subnet
  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  associate_public_ip_address = true

  tags = {
    Name        = "${var.image_name_prefix}-{{timestamp}}"
    OS          = "RHEL9"
    Hardening   = "CIS"
    BuiltBy     = "Packer"
    BuildDate   = "{{isotime \"2006-01-02\"}}"
    Environment = "production"
  }
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build {
  name    = "rhel9-aws"
  sources = ["source.amazon-ebs.rhel9"]

  # 1. Wait for cloud-init to finish before doing anything
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait || true",
    ]
  }

  # 2. Apply CIS hardening
  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/cis-harden.sh"]
  }

  # 3. Install common agents (CloudWatch, SSM, etc.)
  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/install-agents.sh"]
    environment_vars = ["CLOUD=aws"]
  }

  # 4. Final cleanup pass — remove SSH keys, machine-id, bash history
  provisioner "shell" {
    execute_command = "echo '' | sudo -S -E bash '{{.Path}}'"
    scripts         = ["../scripts/cleanup.sh"]
  }

  # Manifest for downstream automation
  post-processor "manifest" {
    output     = "manifest-aws.json"
    strip_path = true
  }
}
