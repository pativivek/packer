#!/usr/bin/env bash
###############################################################################
#  install-agents.sh
#  Installs the cloud-specific agents we want present on every golden image.
#  Set environment variable CLOUD=aws|azure|gcp before running.
###############################################################################
set -euo pipefail
log() { echo -e "\033[1;34m[install-agents]\033[0m $*"; }

CLOUD="${CLOUD:-aws}"
log "Installing common + ${CLOUD} agents"

# -- Common tools every image should have ---------------------------------
dnf -y install \
  vim-enhanced \
  curl \
  wget \
  jq \
  unzip \
  bind-utils \
  net-tools \
  chrony

systemctl enable --now chronyd

# -- Per-cloud agents -----------------------------------------------------
case "$CLOUD" in
  aws)
    log "Installing AWS SSM Agent + CloudWatch Agent"
    dnf -y install https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm || true
    systemctl enable amazon-ssm-agent || true

    rpm -Uvh https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm || true
    ;;

  azure)
    log "Azure Linux Agent (waagent) is preinstalled on RedHat marketplace images."
    # Optionally install azure-cli for diagnostics:
    # rpm --import https://packages.microsoft.com/keys/microsoft.asc
    # dnf -y install azure-cli || true
    ;;

  gcp)
    log "GCP guest tools are preinstalled on rhel-cloud images. Verifying..."
    systemctl is-enabled google-guest-agent || true
    systemctl is-enabled google-osconfig-agent || true
    ;;

  *)
    log "Unknown CLOUD=$CLOUD — skipping cloud-specific install."
    ;;
esac

log "Agent install complete."
