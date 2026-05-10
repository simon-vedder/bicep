#!/bin/bash
set -e

. /etc/os-release

# ── Kernel / sysctl hardening ─────────────────────────────────────────────────
cat > /etc/sysctl.d/99-cis-hardening.conf << 'EOF'
# Disable IPv4 forwarding
net.ipv4.ip_forward = 0
# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1
# Disable ICMP broadcast responses
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Log martians
net.ipv4.conf.all.log_martians = 1
# Restrict dmesg to root
kernel.dmesg_restrict = 1
# Restrict access to kernel pointers
kernel.kptr_restrict = 2
# Disable magic SysRq key
kernel.sysrq = 0
EOF
sysctl -p /etc/sysctl.d/99-cis-hardening.conf

# ── SSH hardening ─────────────────────────────────────────────────────────────
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 4/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

# ── Disable unused filesystems ────────────────────────────────────────────────
cat > /etc/modprobe.d/cis-disable-fs.conf << 'EOF'
install cramfs /bin/false
install freevxfs /bin/false
install hfs /bin/false
install hfsplus /bin/false
install jffs2 /bin/false
install squashfs /bin/false
install udf /bin/false
EOF

# ── Disable unused network protocols ─────────────────────────────────────────
cat > /etc/modprobe.d/cis-disable-net.conf << 'EOF'
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
EOF

# ── File permissions ──────────────────────────────────────────────────────────
chmod 600 /etc/crontab 2>/dev/null || true
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly 2>/dev/null || true
chmod 600 /etc/ssh/sshd_config

# ── Firewall ──────────────────────────────────────────────────────────────────
case "$ID" in
  ubuntu)
    apt-get install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw --force enable
    ;;
  rhel)
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --set-default-zone=drop
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    ;;
esac

# ── Disable legacy services ───────────────────────────────────────────────────
for svc in telnet rsh rlogin rexec tftp xinetd; do
  systemctl disable "$svc" 2>/dev/null || true
  systemctl stop "$svc" 2>/dev/null || true
done

echo "Security hardening completed successfully."
