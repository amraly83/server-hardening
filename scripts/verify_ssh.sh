#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/ssh_verify.log"
SSH_USER="amraly"
SSH_DIR="/home/${SSH_USER}/.ssh"

log_message() {
    local message="$1"
    echo "$message" | tee -a "$LOGFILE"
}

# Check if we're running on the actual server
is_server() {
    if [[ $EUID -ne 0 ]]; then
        log_message "Error: This script must be run as root"
        return 1
    fi
    if [[ ! -d "/etc/ssh" ]]; then
        log_message "Error: /etc/ssh directory not found"
        return 1
    fi
    return 0
}

setup_logging() {
    local log_dir
    log_dir="$(dirname "$LOGFILE")"
    
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        echo "Error: Failed to create log directory: $log_dir"
        return 1
    fi
    
    if ! touch "$LOGFILE" 2>/dev/null; then
        echo "Error: Failed to create or access log file: $LOGFILE"
        return 1
    fi
    
    return 0
}

verify_ssh_keys() {
    local key_issues=0
    
    # Check SSH host keys
    for key in /etc/ssh/ssh_host_*_key; do
        if [[ ! -f "$key" ]]; then
            log_message "ERROR: Missing SSH host key: $key"
            key_issues=1
            continue
        fi
        
        if [ "$(stat -c %a "$key")" != "600" ]; then
            log_message "ERROR: Incorrect permissions on $key"
            key_issues=1
        fi
    done
    
    # Verify only secure key types are used
    if ssh -Q key 2>/dev/null | grep -qE 'ssh-rsa|ssh-dss'; then
        log_message "ERROR: Insecure key types enabled"
        key_issues=1
    fi
    
    # Check authorized_keys permissions
    while IFS= read -r -d '' keyfile; do
        if [ "$(stat -c %a "$keyfile" 2>/dev/null)" != "600" ]; then
            log_message "ERROR: Incorrect permissions on $keyfile"
            key_issues=1
        fi
    done < <(find /home -name "authorized_keys" -type f -print0 2>/dev/null)
    
    return $key_issues
}

setup_ssh_directory() {
    local user=$1
    local ssh_dir="/home/${user}/.ssh"
    
    # Check if user exists
    if ! id -u "${user}" >/dev/null 2>&1; then
        log_message "Error: User ${user} does not exist"
        return 1
    fi
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "${ssh_dir}" ]; then
        log_message "Creating ${ssh_dir}"
        if ! mkdir -p "${ssh_dir}"; then
            log_message "Error: Failed to create ${ssh_dir}"
            return 1
        fi
    fi
    
    # Create authorized_keys if it doesn't exist
    if [ ! -f "${ssh_dir}/authorized_keys" ]; then
        log_message "Creating ${ssh_dir}/authorized_keys"
        if ! touch "${ssh_dir}/authorized_keys"; then
            log_message "Error: Failed to create authorized_keys file"
            return 1
        fi
    fi
    
    # Set correct permissions with error checking
    if ! chmod 700 "${ssh_dir}"; then
        log_message "Error: Failed to set permissions on ${ssh_dir}"
        return 1
    fi
    
    if ! chmod 600 "${ssh_dir}/authorized_keys"; then
        log_message "Error: Failed to set permissions on authorized_keys"
        return 1
    fi
    
    if ! chown -R "${user}:${user}" "${ssh_dir}"; then
        log_message "Error: Failed to set ownership for ${ssh_dir}"
        return 1
    fi
    
    log_message "SSH directory setup completed for ${user}"
    return 0
}

main() {
    local exit_code=0
    
    log_message "Starting SSH verification process at $(date)"
    
    # Step 1: Check if we're running on server
    if ! is_server; then
        log_message "Running in local development mode - skipping system modifications"
        LOGFILE="./ssh_verify.log"
        return 0
    fi
    
    # Step 2: Setup logging
    if ! setup_logging; then
        log_message "Failed to setup logging"
        return 1
    fi
    
    # Step 3: Setup SSH directory structure
    if ! setup_ssh_directory "${SSH_USER}"; then
        log_message "Failed to setup SSH directory for ${SSH_USER}"
        return 1
    fi
    
    # Step 4: Verify SSH directory structure
    log_message "Verifying SSH directory structure..."
    if ! ls -la "${SSH_DIR}/" >> "$LOGFILE" 2>&1; then
        log_message "Failed to verify SSH directory structure"
        return 1
    fi
    
    # Step 5: Verify SSH keys and permissions
    if ! verify_ssh_keys; then
        log_message "SSH key verification failed"
        exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_message "SSH verification completed successfully"
    else
        log_message "SSH verification completed with errors"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"