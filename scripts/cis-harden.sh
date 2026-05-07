#!/usr/bin/env bash
###############################################################################
#  cis-harden.sh
#  Lightweight CIS Benchmark hardening for RHEL 9 / Oracle Linux 8-9.
#
#  This is a starter script — covers the highest-impact, low-risk controls.
#  For full compliance, layer in OpenSCAP scans + the SCAP Security Guide
#  (scap-security-guide package) to apply the complete profile.
#
#  Sections (mapped roughly to CIS RHEL 9 Benchmark v1.0.0):
#    1. Filesystem & kernel module restrictions
#    2. Unwanted packages / services
#    3. Network & firewall
#    4. Logging & auditing
#    5. SSH hardening
#    6. Password & account policies
#    7. Updates
###############################################################################
set -euo pipefail

log() { echo -e "\033[1;32m[cis-harden]\033[0m $*"; }

# Detect distro family
. /etc/os-release
DIST="${ID,,}"
log "Hardening ${PRETTY_NAME}"

# ---------------------------------------------------------------------------
# 1. Filesystem & kernel module restrictions
# ---------------------------------------------------------------------------
log "Section 1 — disabling unused filesystem modules"
cat >/etc/modprobe.d/cis-disable-fs.conf <<'EOF'
install cramfs   /bin/true
install freevxfs /bin/true
install hfs      /bin/true
install hfsplus  /bin/true
install jffs2    /bin/true
install squashfs /bin/true
install udf      /bin/true
install usb-storage /bin/true
EOF

# ---------------------------------------------------------------------------
# 2. Remove / disable risky packages and services
# ---------------------------------------------------------------------------
log "Section 2 — removing legacy services"
LEGACY_PKGS=(telnet-server rsh-server ypserv tftp-server xinetd)
for pkg in "${LEGACY_PKGS[@]}"; do
  rpm -q "$pkg" >/dev/null 2>&1 && dnf -y remove "$pkg" || true
done

LEGACY_SVCS=(rsh.socket rlogin.socket rexec.socket telnet.socket tftp.socket avahi-daemon)
for svc in "${LEGACY_SVCS[@]}"; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# 3. Network & firewall
# ---------------------------------------------------------------------------
log "Section 3 — kernel network parameters"
cat >/etc/sysctl.d/60-cis-network.conf <<'EOF'
# Disable IP forwarding (unless this is a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Disable send / accept of ICMP redirects
net.ipv4.conf.all.send_redirects     = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects   = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects   = 0

# Source-routed packets
net.ipv4.conf.all.accept_source_route     = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route     = 0

# Reverse-path filtering
net.ipv4.conf.all.rp_filter     = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore broadcast pings & bogus error responses
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Log martians
net.ipv4.conf.all.log_martians     = 1
net.ipv4.conf.default.log_martians = 1

# TCP SYN cookies
net.ipv4.tcp_syncookies = 1
EOF
sysctl --system >/dev/null

# Ensure firewalld is enabled (most clouds replace this with security groups,
# but the CIS guide expects a host firewall to be present).
if rpm -q firewalld >/dev/null 2>&1; then
  systemctl enable firewalld
fi

# ---------------------------------------------------------------------------
# 4. Auditing & logging
# ---------------------------------------------------------------------------
log "Section 4 — enabling auditd"
dnf -y install audit rsyslog
systemctl enable --now auditd rsyslog

cat >/etc/audit/rules.d/cis.rules <<'EOF'
# CIS audit rules — minimum recommended set
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k actions
-w /etc/sudoers.d/ -p wa -k actions
-w /var/log/lastlog -p wa -k logins
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
-a always,exit -F arch=b64 -S execve -k execlog
-e 2
EOF

# Make rsyslog config a bit safer
cat >/etc/rsyslog.d/60-cis.conf <<'EOF'
$FileCreateMode 0640
$umask 0027
EOF

# ---------------------------------------------------------------------------
# 5. SSH hardening
# ---------------------------------------------------------------------------
log "Section 5 — hardening sshd_config"
SSHD=/etc/ssh/sshd_config

# helper: set a key to a value (replace existing or append)
set_sshd() {
  local key="$1" value="$2"
  if grep -Eq "^[[:space:]]*${key}\b" "$SSHD"; then
    sed -ri "s|^[[:space:]]*${key}\b.*|${key} ${value}|" "$SSHD"
  else
    echo "${key} ${value}" >> "$SSHD"
  fi
}

set_sshd Protocol 2
set_sshd PermitRootLogin no
set_sshd PermitEmptyPasswords no
set_sshd PasswordAuthentication no
set_sshd X11Forwarding no
set_sshd MaxAuthTries 4
set_sshd ClientAliveInterval 300
set_sshd ClientAliveCountMax 0
set_sshd LoginGraceTime 60
set_sshd Banner /etc/issue.net
set_sshd LogLevel VERBOSE
set_sshd UsePAM yes

cat >/etc/issue.net <<'EOF'
###############################################################################
# Authorised access only. All activity is monitored and logged.
###############################################################################
EOF

chmod 600 "$SSHD"

# ---------------------------------------------------------------------------
# 6. Password & account policies
# ---------------------------------------------------------------------------
log "Section 6 — password policy"

# Password aging
sed -ri 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/'   /etc/login.defs
sed -ri 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS    7/'   /etc/login.defs
sed -ri 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/'   /etc/login.defs

# Default umask
echo 'umask 027' >/etc/profile.d/cis-umask.sh
chmod 644 /etc/profile.d/cis-umask.sh

# Restrict cron / at to root
for f in /etc/cron.allow /etc/at.allow; do
  echo root > "$f"
  chmod 600 "$f"
done
rm -f /etc/cron.deny /etc/at.deny

# Lock unused system accounts
for u in games ftp; do
  id "$u" &>/dev/null && passwd -l "$u" || true
done

# ---------------------------------------------------------------------------
# 7. Patch the system
# ---------------------------------------------------------------------------
log "Section 7 — applying security updates"
dnf -y upgrade-minimal --security || dnf -y upgrade

log "CIS hardening complete."
