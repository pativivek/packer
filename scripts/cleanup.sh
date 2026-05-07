#!/usr/bin/env bash
###############################################################################
#  cleanup.sh
#  Final pass before the image is captured. Removes anything that would make
#  one VM identifiable (host keys, machine-id, history, dnf cache, logs).
###############################################################################
set -euo pipefail
log() { echo -e "\033[1;33m[cleanup]\033[0m $*"; }

log "Removing SSH host keys (will be regenerated on first boot)"
rm -f /etc/ssh/ssh_host_*

log "Resetting machine-id"
truncate -s 0 /etc/machine-id
[ -f /var/lib/dbus/machine-id ] && rm -f /var/lib/dbus/machine-id

log "Cleaning dnf cache"
dnf clean all
rm -rf /var/cache/dnf/*

log "Truncating logs"
find /var/log -type f -exec truncate -s 0 {} \;

log "Removing bash history & temp files"
rm -rf /root/.bash_history /home/*/.bash_history /tmp/* /var/tmp/*

# Remove cloud-init state so it re-runs on first boot of a new instance
log "Resetting cloud-init"
cloud-init clean --logs --seed 2>/dev/null || rm -rf /var/lib/cloud/* /var/log/cloud-init*.log

log "Cleanup complete."
