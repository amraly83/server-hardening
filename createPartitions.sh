#!/bin/bash

set -euo pipefail

# Pre-flight system validation
validate_system() {
    # Required system packages
    local required_packages=(
        "jq"
        "rsync"
        "mailutils"
        "auditd"
        "apparmor"
        "fail2ban"
        "aide"
        "rkhunter"
    )
    
    # Install dependencies
    apt-get update
    for pkg in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            apt-get install -y "$pkg"
        fi
    done
    
    # Verify system time synchronization
    if ! timedatectl status | grep -q "System clock synchronized: yes"; then
        systemctl start systemd-timesyncd
        timedatectl set-ntp true
    fi
    
    # Ensure required directories
    mkdir -p /var/log/hardening
    mkdir -p /etc/hardening
    mkdir -p /opt/hardening
    
    # Set up logging
    if [ ! -f "/etc/rsyslog.d/hardening.conf" ]; then
        cat > "/etc/rsyslog.d/hardening.conf" << EOF
if \$programname == 'hardening' then /var/log/hardening/system.log
& stop
EOF
        systemctl restart rsyslog
    fi
}

# Install monitoring components
setup_monitoring() {
    # Copy scripts to final location
    cp ./monitor_security.sh /opt/hardening/
    cp ./scripts/cluster_sync.sh /opt/hardening/
    chmod +x /opt/hardening/*.sh
    
    # Install systemd services
    cp ./config/hardening-monitor.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable hardening-monitor
}

# Configure backup system
setup_backups() {
    # Create backup script
    cat > /opt/hardening/backup-security-config.sh << EOF
#!/bin/bash
BACKUP_DIR="/var/backups/hardening/\$(date +%Y%m%d)"
mkdir -p "\$BACKUP_DIR"

# Backup security configurations
cp -r /etc/ssh "\$BACKUP_DIR/"
cp -r /etc/pam.d "\$BACKUP_DIR/"
cp -r /etc/security "\$BACKUP_DIR/"
cp -r /var/lib/hardening "\$BACKUP_DIR/"
cp -r /etc/hardening "\$BACKUP_DIR/"

# Compress backup
tar -czf "\$BACKUP_DIR.tar.gz" "\$BACKUP_DIR"
rm -rf "\$BACKUP_DIR"

# Retain only last 7 days
find /var/backups/hardening -name "*.tar.gz" -mtime +7 -delete
EOF
    
    chmod +x /opt/hardening/backup-security-config.sh
    
    # Setup daily cron job for backups
    echo "0 2 * * * root /opt/hardening/backup-security-config.sh" > /etc/cron.d/hardening-backup
}

# Main setup function
main() {
    echo "Starting system preparation..."
    
    validate_system
    setup_monitoring
    setup_backups
    
    echo "System preparation completed successfully"
}

main "$@"

if lsblk | grep '^sdc.*5G'; then
  mv /home/vagrant/.ssh /root/vagrant-ssh

  fdisk -u /dev/sdc <<EOF
n
p
1

+500M
n
p
2

+500M
n
p
3

+500M
n
p
4

+500M
w
EOF

  mkfs.xfs /dev/sdc1
  mkfs.xfs /dev/sdc2
  mkfs.xfs /dev/sdc3
  mkfs.xfs /dev/sdc4

  mkdir -p /var/log/audit
  mkdir -p /var/lib/docker

  {
    echo '/dev/sdc1 /var/log xfs defaults 0 0'
    echo '/dev/sdc2 /var/log/audit xfs defaults 0 0'
    echo '/dev/sdc3 /home xfs defaults 0 0'
    echo '/dev/sdc4 /var/lib/docker xfs defaults 0 0'
  } >> /etc/fstab

  mount -t xfs /dev/sdc1 /var/log
  mount -t xfs /dev/sdc2 /var/log/audit
  mount -t xfs /dev/sdc3 /home
  mount -t xfs /dev/sdc4 /var/lib/docker

  if grep '^vagrant' /etc/passwd; then
    mkdir -p /home/vagrant
    mv /root/vagrant-ssh /home/vagrant/.ssh
    chown -R vagrant:vagrant /home/vagrant
    chmod 0750 /home/vagrant
    chmod 0700 /home/vagrant/.ssh
    chmod 0600 /home/vagrant/.ssh/*
  fi
fi
