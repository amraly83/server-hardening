#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/ssh_verify.log"

verify_ssh_keys() {
    local key_issues=0
    
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
    
    return $key_issues
}

# Ensure correct SSH directory permissions
chmod 700 /home/amraly/.ssh
chmod 600 /home/amraly/.ssh/authorized_keys
chown -R amraly:amraly /home/amraly/.ssh

# Verify permissions
echo "Verifying SSH permissions..."
ls -la /home/amraly/.ssh/

# Main verification
echo "Starting SSH key verification at $(date)" | tee -a "$LOGFILE"
if ! verify_ssh_keys 2>&1 | tee -a "$LOGFILE"; then
    echo "SSH key verification failed, check $LOGFILE for details"
    exit 1
fi
echo "SSH key verification completed successfully" | tee -a "$LOGFILE"