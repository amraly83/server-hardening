#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/ssh_verify.log"
SSH_USER="amraly"
SSH_DIR="/home/${SSH_USER}/.ssh"
BACKUP_DIR="/var/backups/hardening/ssh"
SSH_CONFIG="/etc/ssh/sshd_config"

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOGFILE"
}

ensure_directories() {
    # Create log and backup directories with proper permissions
    for dir in "$(dirname "$LOGFILE")" "$BACKUP_DIR"; do
        if ! mkdir -p "$dir"; then
            echo "Failed to create directory: $dir" >&2
            return 1
        fi
        chmod 750 "$dir"
    done
}

backup_ssh_config() {
    if ! ensure_directories; then
        return 1
    fi
    
    # Backup SSH configuration
    if [ -f "$SSH_CONFIG" ]; then
        cp -p "$SSH_CONFIG" "${BACKUP_DIR}/sshd_config_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Backup user SSH directory
    if [ -d "$SSH_DIR" ]; then
        cp -rp "$SSH_DIR" "${BACKUP_DIR}/ssh_backup_$(date +%Y%m%d_%H%M%S)"
    fi
}

verify_user_exists() {
    if ! getent passwd "$SSH_USER" >/dev/null; then
        log_message "User $SSH_USER does not exist" "ERROR"
        return 1
    fi
    
    if ! groups "$SSH_USER" | grep -qE '(sudo|wheel)'; then
        log_message "User $SSH_USER is not in sudoers group" "WARNING"
    fi
    return 0
}

verify_ssh_keys() {
    local key_issues=0
    
    # Check SSH host keys
    if ! [ -d "/etc/ssh" ]; then
        log_message "SSH directory /etc/ssh does not exist" "ERROR"
        return 1
    fi
    
    # Verify host keys exist and have correct permissions
    for keytype in rsa ecdsa ed25519; do
        local keyfile="/etc/ssh/ssh_host_${keytype}_key"
        if [ ! -f "$keyfile" ]; then
            log_message "Missing SSH host key: $keyfile" "ERROR"
            key_issues=1
            continue
        fi
        
        # Check permissions and ownership
        if [ "$(stat -c %a "$keyfile")" != "600" ] || [ "$(stat -c %U:%G "$keyfile")" != "root:root" ]; then
            log_message "Incorrect permissions/ownership on $keyfile" "ERROR"
            chmod 600 "$keyfile"
            chown root:root "$keyfile"
            key_issues=1
        fi
    done
    
    # Check for insecure key types
    if ssh -Q key 2>/dev/null | grep -qE 'ssh-rsa|ssh-dss|ecdsa-sha2-nistp256'; then
        log_message "Insecure key types enabled" "ERROR"
        key_issues=1
    fi
    
    return $key_issues
}

setup_ssh_directory() {
    log_message "Setting up SSH directory for $SSH_USER"
    
    local user_home
    user_home=$(getent passwd "$SSH_USER" | cut -d: -f6)
    
    if [ ! -d "$user_home" ]; then
        log_message "Home directory $user_home does not exist" "ERROR"
        return 1
    fi
    
    # Create .ssh directory with proper ownership first
    if ! mkdir -p "$SSH_DIR"; then
        log_message "Failed to create $SSH_DIR" "ERROR"
        return 1
    fi
    chown "$SSH_USER:$SSH_USER" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # Create authorized_keys with proper permissions
    if ! [ -f "$SSH_DIR/authorized_keys" ]; then
        touch "$SSH_DIR/authorized_keys"
        chown "$SSH_USER:$SSH_USER" "$SSH_DIR/authorized_keys"
        chmod 600 "$SSH_DIR/authorized_keys"
    fi
    
    return 0
}

verify_permissions() {
    local has_errors=0
    
    # Verify SSH directory permissions
    if ! [ -d "$SSH_DIR" ]; then
        log_message "$SSH_DIR does not exist" "ERROR"
        return 1
    fi
    
    local dir_perms
    dir_perms=$(stat -c %a "$SSH_DIR")
    if [ "$dir_perms" != "700" ]; then
        log_message "Fixing incorrect permissions on $SSH_DIR (found: $dir_perms)" "WARNING"
        chmod 700 "$SSH_DIR"
        has_errors=1
    fi
    
    # Verify authorized_keys permissions
    if [ -f "$SSH_DIR/authorized_keys" ]; then
        local file_perms
        file_perms=$(stat -c %a "$SSH_DIR/authorized_keys")
        if [ "$file_perms" != "600" ]; then
            log_message "Fixing incorrect permissions on authorized_keys (found: $file_perms)" "WARNING"
            chmod 600 "$SSH_DIR/authorized_keys"
            has_errors=1
        fi
        
        # Verify ownership
        local ownership
        ownership=$(stat -c %U:%G "$SSH_DIR/authorized_keys")
        if [ "$ownership" != "$SSH_USER:$SSH_USER" ]; then
            log_message "Fixing incorrect ownership on authorized_keys (found: $ownership)" "WARNING"
            chown "$SSH_USER:$SSH_USER" "$SSH_DIR/authorized_keys"
            has_errors=1
        fi
    fi
    
    return $has_errors
}

main() {
    local exit_code=0
    
    log_message "Starting SSH verification process"
    
    # Step 1: Create directories and verify user
    if ! ensure_directories || ! verify_user_exists; then
        log_message "Initial verification failed" "ERROR"
        exit 1
    fi
    
    # Step 2: Create backup
    if ! backup_ssh_config; then
        log_message "Backup creation failed" "ERROR"
        exit 1
    fi
    
    # Step 3: Setup SSH directory structure
    if ! setup_ssh_directory; then
        log_message "Failed to setup SSH directory structure" "ERROR"
        exit 1
    fi
    
    # Step 4: Verify SSH host keys
    if ! verify_ssh_keys; then
        log_message "SSH key verification failed" "ERROR"
        exit_code=1
    fi
    
    # Step 5: Verify and fix permissions
    if ! verify_permissions; then
        log_message "Permission verification/fix required changes" "WARNING"
        exit_code=1
    fi
    
    # Final status
    if [ $exit_code -eq 0 ]; then
        log_message "SSH verification completed successfully" "SUCCESS"
    else
        log_message "SSH verification completed with issues" "WARNING"
    fi
    
    return $exit_code
}

# Execute main function with error handling
if ! main "$@"; then
    log_message "SSH verification failed" "ERROR"
    exit 1
fi