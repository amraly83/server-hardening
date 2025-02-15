#!/bin/bash

set -euo pipefail

# Restoration script for hardening deployment

BACKUP_DIR=""
LOGFILE="recovery-$(hostname --short)-$(date +%y%m%d).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Find most recent backup
find_latest_backup() {
    BACKUP_DIR=$(ls -td /root/hardening_backup_* | head -n1)
    if [ -z "$BACKUP_DIR" ]; then
        log "No backup directory found"
        exit 1
    fi
}

# Restore critical files
restore_files() {
    log "Restoring from backup: $BACKUP_DIR"
    
    for file in "$BACKUP_DIR"/*; do
        original_path="/etc/${file##*/}"
        if [ -f "$file" ]; then
            cp -p "$file" "$original_path"
            log "Restored: $original_path"
        fi
    done
}

# Reset SSH configuration
reset_ssh() {
    log "Resetting SSH configuration..."
    
    # Restore default port
    sed -i 's/^Port .*/Port 22/' /etc/ssh/sshd_config
    
    # Enable password authentication temporarily
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    systemctl restart sshd
}

# Reset firewall rules
reset_firewall() {
    log "Resetting firewall rules..."
    
    ufw --force reset
    ufw allow 22/tcp
    ufw --force enable
}

# Main recovery function
main() {
    log "Starting recovery process..."
    
    find_latest_backup
    restore_files
    reset_ssh
    reset_firewall
    
    log "Recovery completed. Please verify system access."
}

main "$@"