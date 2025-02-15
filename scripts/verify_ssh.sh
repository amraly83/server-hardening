#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/ssh_verify.log"
SSH_USER="amraly"
SSH_DIR="/home/${SSH_USER}/.ssh"

# Check if we're running on the actual server
is_server() {
    # Check if we're root and if /etc/ssh exists (typical server environment)
    [[ $EUID -eq 0 ]] && [[ -d "/etc/ssh" ]]
}

verify_ssh_keys() {
    local key_issues=0
    
    # Only perform these checks if we're on the actual server
    if is_server; then
        # Check SSH host keys
        for key in /etc/ssh/ssh_host_*_key; do
            if [ "$(stat -c %a "$key")" != "600" ]; then
                echo "ERROR: Incorrect permissions on $key"
                key_issues=1
            fi
        done
        
        # Verify only secure key types are used
        if ssh -Q key | grep -qE 'ssh-rsa|ssh-dss'; then
            echo "ERROR: Insecure key types enabled"
            key_issues=1
        fi
        
        # Check authorized_keys permissions
        find /home -name "authorized_keys" -type f | while read -r keyfile; do
            if [ "$(stat -c %a "$keyfile")" != "600" ]; then
                echo "ERROR: Incorrect permissions on $keyfile"
                key_issues=1
            fi
        done
    else
        echo "Running in local development mode - skipping system-level SSH checks"
    fi
    
    return $key_issues
}

setup_ssh_directory() {
    local user=$1
    local ssh_dir="/home/${user}/.ssh"
    
    # Check if user exists
    if ! id -u "${user}" >/dev/null 2>&1; then
        echo "Error: User ${user} does not exist"
        return 1
    }
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "${ssh_dir}" ]; then
        echo "Creating ${ssh_dir}"
        mkdir -p "${ssh_dir}"
    fi
    
    # Create authorized_keys if it doesn't exist
    if [ ! -f "${ssh_dir}/authorized_keys" ]; then
        echo "Creating ${ssh_dir}/authorized_keys"
        touch "${ssh_dir}/authorized_keys"
    fi
    
    # Set correct permissions
    chmod 700 "${ssh_dir}"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${user}:${user}" "${ssh_dir}"
    
    echo "SSH directory setup completed for ${user}"
    return 0
}

# Only perform system modifications if we're on the actual server
if is_server; then
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOGFILE")"
    
    # Setup SSH directory structure with error handling
    if ! setup_ssh_directory "${SSH_USER}"; then
        echo "Failed to setup SSH directory for ${SSH_USER}"
        exit 1
    fi
    
    # Verify permissions
    echo "Verifying SSH permissions..."
    ls -la "${SSH_DIR}/"
else
    echo "Running in local development mode - skipping system modifications"
    LOGFILE="./ssh_verify.log"
fi

# Main verification
echo "Starting SSH key verification at $(date)" | tee -a "$LOGFILE"
if ! verify_ssh_keys 2>&1 | tee -a "$LOGFILE"; then
    echo "SSH key verification failed, check $LOGFILE for details"
    exit 1
fi
echo "SSH key verification completed successfully" | tee -a "$LOGFILE"