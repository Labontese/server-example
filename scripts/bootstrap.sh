#!/usr/bin/env bash
# ============================================================
# Dedicated Server Post-Install Script
# Target OS: Ubuntu 24.04 LTS (Noble Numbat)
# Run as root on a fresh installation
#
# What this script does:
#   1. System update + essential packages
#   2. Timezone + locale
#   3. Creates non-root service user with SSH keys
#   4. SSH hardening (no root, no password, key-only)
#   5. Firewall (UFW) - only 22, 80, 443
#   6. Fail2ban for brute-force protection
#   7. Kernel + network tuning for high-traffic server
#   8. Docker CE + Compose plugin
#   9. Docker daemon tuning (log rotation, live-restore)
#  10. Automatic security updates (unattended-upgrades)
#  11. NTP time sync
#  12. Swap configuration (small, for safety)
#  13. Misc hardening (shared memory, core dumps, snap removal)
# ============================================================
set -euo pipefail

# --- Configuration ---
SERVICE_USER="appuser"   # Change this to your preferred username

# --- Preflight checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
  echo "WARNING: This script is designed for Ubuntu 24.04. Proceeding anyway..."
fi

echo "============================================"
echo "  Server Bootstrap - Ubuntu 24.04"
echo "============================================"
echo ""

# ============================================================
# 1. SYSTEM UPDATE + ESSENTIAL PACKAGES
# ============================================================
echo ">>> [1/13] Updating system and installing packages..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get dist-upgrade -y

apt-get install -y \
  curl wget git htop iotop ncdu unzip jq tree \
  ufw fail2ban \
  apache2-utils \
  ca-certificates gnupg lsb-release \
  logrotate \
  net-tools dnsutils \
  chrony \
  rsync \
  vim nano \
  acl \
  libpam-tmpdir

echo ">>> System packages installed"

# ============================================================
# 2. TIMEZONE + LOCALE
# ============================================================
echo ">>> [2/13] Configuring timezone and locale..."

timedatectl set-timezone Europe/Stockholm  # Change to your timezone

locale-gen en_US.UTF-8 2>/dev/null || true
update-locale LANG=en_US.UTF-8

echo ">>> Timezone and locale configured"

# ============================================================
# 3. CREATE SERVICE USER
# ============================================================
echo ">>> [3/13] Creating service user..."

if ! id "$SERVICE_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G sudo "$SERVICE_USER"
  echo "$SERVICE_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$SERVICE_USER"
  chmod 440 "/etc/sudoers.d/$SERVICE_USER"

  mkdir -p "/home/$SERVICE_USER/.ssh"
  # Copy root's authorized_keys so you can SSH in as the service user
  cp /root/.ssh/authorized_keys "/home/$SERVICE_USER/.ssh/authorized_keys" 2>/dev/null || true
  chown -R "$SERVICE_USER:$SERVICE_USER" "/home/$SERVICE_USER/.ssh"
  chmod 700 "/home/$SERVICE_USER/.ssh"
  chmod 600 "/home/$SERVICE_USER/.ssh/authorized_keys" 2>/dev/null || true
  echo ">>> Created $SERVICE_USER user (with your SSH key)"
else
  echo ">>> $SERVICE_USER user already exists, skipping"
fi

# ============================================================
# 4. SSH HARDENING
# ============================================================
echo ">>> [4/13] Hardening SSH..."

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)

cat > /etc/ssh/sshd_config.d/99-hardened.conf <<SSHD
# --- Authentication ---
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
MaxAuthTries 3
MaxSessions 5

# --- Disable unused auth methods ---
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no

# --- Session ---
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# --- Forwarding ---
AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no

# --- Security ---
HostbasedAuthentication no
IgnoreRhosts yes
UseDNS no
DebianBanner no

# --- Restrict to service user ---
AllowUsers $SERVICE_USER
SSHD

sshd -t && systemctl restart ssh
echo ">>> SSH hardened (root disabled, key-only, $SERVICE_USER user only)"

# ============================================================
# 5. FIREWALL (UFW)
# ============================================================
echo ">>> [5/13] Configuring firewall..."

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

ufw --force enable
echo ">>> Firewall: only SSH (22), HTTP (80), HTTPS (443) open"

# ============================================================
# 6. FAIL2BAN
# ============================================================
echo ">>> [6/13] Configuring Fail2ban..."

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
banaction = ufw

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
JAIL

systemctl enable fail2ban
systemctl restart fail2ban
echo ">>> Fail2ban: 3 failed SSH attempts = 1 hour ban (using UFW)"

# ============================================================
# 7. KERNEL + NETWORK TUNING
# ============================================================
echo ">>> [7/13] Tuning kernel and network..."

cat > /etc/sysctl.d/99-server-tuning.conf <<'SYSCTL'
# ---- Network performance ----
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fastopen = 3

# ---- TCP optimizations ----
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# ---- Connection tracking ----
net.netfilter.nf_conntrack_max = 262144

# ---- Security ----
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ---- File descriptors ----
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# ---- VM tuning (adjust swappiness for your RAM) ----
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
vm.vfs_cache_pressure = 50
vm.max_map_count = 262144
SYSCTL

sysctl -p /etc/sysctl.d/99-server-tuning.conf
echo ">>> Kernel tuned (network, TCP, security, VM)"

# ============================================================
# 8. INSTALL DOCKER
# ============================================================
echo ">>> [8/13] Installing Docker..."

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker "$SERVICE_USER"
echo ">>> Docker CE + Compose plugin installed"

# ============================================================
# 9. DOCKER DAEMON TUNING
# ============================================================
echo ">>> [9/13] Configuring Docker daemon..."

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DAEMON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-address-pools": [
    {"base": "172.20.0.0/16", "size": 24}
  ],
  "metrics-addr": "127.0.0.1:9323"
}
DAEMON

systemctl restart docker
echo ">>> Docker daemon: log rotation, overlay2, live-restore"

# ============================================================
# 10. AUTOMATIC SECURITY UPDATES
# ============================================================
echo ">>> [10/13] Enabling automatic security updates..."

apt-get install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTO

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED

echo ">>> Auto security updates enabled (no auto-reboot)"

# ============================================================
# 11. NTP TIME SYNC
# ============================================================
echo ">>> [11/13] Configuring time sync..."

systemctl enable chrony
systemctl start chrony
echo ">>> Time sync via chrony"

# ============================================================
# 12. SWAP (small safety net)
# ============================================================
echo ">>> [12/13] Configuring swap..."

if ! swapon --show | grep -q "/swapfile"; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo ">>> 2GB swap created (swappiness=10, emergency use only)"
else
  echo ">>> Swap already exists, skipping"
fi

# ============================================================
# 13. MISC HARDENING
# ============================================================
echo ">>> [13/13] Final hardening..."

# Shared memory hardening
if ! grep -q "tmpfs /run/shm" /etc/fstab; then
  echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
fi

# Restrict core dumps
echo '* hard core 0' > /etc/security/limits.d/no-core-dumps.conf
echo 'fs.suid_dumpable = 0' >> /etc/sysctl.d/99-server-tuning.conf
sysctl -w fs.suid_dumpable=0

# Restrict su to sudo group
dpkg-statoverride --update --add root sudo 4750 /usr/bin/su 2>/dev/null || true

# Disable unused services
for svc in apport snapd; do
  if systemctl is-enabled "$svc" 2>/dev/null | grep -q enabled; then
    systemctl disable "$svc"
    systemctl stop "$svc"
    echo ">>> Disabled $svc"
  fi
done

# Remove snap if present
if command -v snap &>/dev/null; then
  snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r pkg; do
    snap remove --purge "$pkg" 2>/dev/null || true
  done
  apt-get purge -y snapd 2>/dev/null || true
  echo ">>> Removed snapd"
fi

# Set file limits for service user
cat > "/etc/security/limits.d/$SERVICE_USER.conf" <<LIMITS
$SERVICE_USER soft nofile 65535
$SERVICE_USER hard nofile 65535
$SERVICE_USER soft nproc  65535
$SERVICE_USER hard nproc  65535
LIMITS

# Login banner
cat > /etc/motd <<'MOTD'
============================================
  Managed Server - Authorized Access Only
============================================
MOTD

echo ">>> Hardening complete"

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "============================================"
echo "  Bootstrap complete!"
echo "============================================"
echo ""
echo "  What was configured:"
echo "    - System updated, essential tools installed"
echo "    - $SERVICE_USER user created (with your SSH key)"
echo "    - SSH: root disabled, password disabled, key-only"
echo "    - Firewall: only ports 22, 80, 443"
echo "    - Fail2ban: 3 attempts = 1 hour ban"
echo "    - Docker CE + Compose installed"
echo "    - Kernel tuned for high-traffic"
echo "    - Auto security updates (no auto-reboot)"
echo "    - NTP time sync via chrony"
echo "    - 2GB emergency swap"
echo "    - Snapd removed, core dumps disabled"
echo ""
echo "  Next steps:"
echo "    1. Log in as $SERVICE_USER:  ssh $SERVICE_USER@$(hostname -I | awk '{print $1}')"
echo "    2. Clone repo:               git clone <repo> ~/server && cd ~/server"
echo "    3. Configure:                cp .env.example .env && nano .env"
echo "    4. Start:                    make up"
echo ""
echo "  WARNING: Root SSH is now disabled."
echo "  Make sure you can SSH as $SERVICE_USER before closing this session!"
echo "============================================"
