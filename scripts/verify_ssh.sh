#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/ssh_verify.log"
SSH_USER="amraly"
SSH_DIR="/home/${SSH_USER}/.ssh"
BACKUP_DIR="/var/backups/hardening/ssh"

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOGFILE"
}

backup_ssh_config() {
    mkdir -p "$BACKUP_DIR"
    if [ -d "$SSH_DIR" ]; then
        cp -r "$SSH_DIR" "${BACKUP_DIR}/ssh_backup_$(date +%Y%m%d_%H%M%S)"
    fi
}

verify_user_exists() {
    if ! id -u "$SSH_USER" >/dev/null 2>&1; then
        log_message "User $SSH_USER does not exist" "ERROR"
        return 1
    fi
    return 0
}

verify_ssh_keys() {
    local key_issues=0
    
    # Check SSH host keys first
    for key in /etc/ssh/ssh_host_*_key; do
        if [[ ! -f "$key" ]]; then
            log_message "Missing SSH host key: $key" "ERROR"
            key_issues=1
            continue
        fi
        
        if [ "$(stat -c %a "$key")" != "600" ]; then
            log_message "Incorrect permissions on $key" "ERROR"
            key_issues=1
        fi
    done
    
    # Verify only secure key types
    if ssh -Q key 2>/dev/null | grep -qE 'ssh-rsa|ssh-dss'; then
        log_message "Insecure key types enabled" "ERROR"
        key_issues=1
    fi
    
    return $key_issues
}

setup_ssh_directory() {
    log_message "Setting up SSH directory for $SSH_USER"
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "$SSH_DIR" ]; then
        if ! mkdir -p "$SSH_DIR"; then
            log_message "Failed to create $SSH_DIR" "ERROR"
            return 1
        fi
    fi
    
    # Create authorized_keys if it doesn't exist
    if [ ! -f "$SSH_DIR/authorized_keys" ]; then
        if ! touch "$SSH_DIR/authorized_keys"; then
            log_message "Failed to create authorized_keys file" "ERROR"
            return 1
        fi
    fi
    
    # Set correct permissions with error checking
    if ! chmod 700 "$SSH_DIR"; then
        log_message "Failed to set permissions on $SSH_DIR" "ERROR"
        return 1
    fi
    
    if ! chmod 600 "$SSH_DIR/authorized_keys"; then
        log_message "Failed to set permissions on authorized_keys" "ERROR"
        return 1
    fi
    
    if ! chown -R "${SSH_USER}:${SSH_USER}" "$SSH_DIR"; then
        log_message "Failed to set ownership for $SSH_DIR" "ERROR"
        return 1
    fi
    
    log_message "SSH directory setup completed for $SSH_USER" "SUCCESS"
    return 0
}

verify_permissions() {
    local has_errors=0
    
    # Verify SSH directory permissions
    if [ "$(stat -c %a "$SSH_DIR")" != "700" ]; then
        log_message "Incorrect permissions on $SSH_DIR" "ERROR"
        has_errors=1
    fi
    
    # Verify authorized_keys permissions
    if [ "$(stat -c %a "$SSH_DIR/authorized_keys")" != "600" ]; then
        log_message "Incorrect permissions on $SSH_DIR/authorized_keys" "ERROR"
        has_errors=1
    fi
    
    # Verify ownership
    if [ "$(stat -c %U:%G "$SSH_DIR")" != "$SSH_USER:$SSH_USER" ]; then
        log_message "Incorrect ownership on $SSH_DIR" "ERROR"
        has_errors=1
    fi
    
    return $has_errors
}

main() {
    local exit_code=0
    
    log_message "Starting SSH verification process"
    
    # Step 1: Verify user exists
    if ! verify_user_exists; then
        exit 1
    fi
    
    # Step 2: Create backup
    backup_ssh_config
    
    # Step 3: Setup SSH directory structure
    if ! setup_ssh_directory; then
        log_message "Failed to setup SSH directory structure" "ERROR"
        exit 1
    fi
    
    # Step 4: Verify SSH keys
    if ! verify_ssh_keys; then
        log_message "SSH key verification failed" "ERROR"
        exit_code=1
    fi
    
    # Step 5: Verify final permissions
    if ! verify_permissions; then
        log_message "Permission verification failed" "ERROR"
        exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_message "SSH verification completed successfully" "SUCCESS"
    else
        log_message "SSH verification completed with errors" "ERROR"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"