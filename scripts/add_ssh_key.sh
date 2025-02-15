#!/bin/bash

set -euo pipefail

MANAGED_KEYS_DIR="/etc/hardening/ssh_keys"
KEY_DISTRIBUTION_LOG="/var/log/hardening/key_distribution.log"

# Initialize key management
init_key_management() {
    mkdir -p "$MANAGED_KEYS_DIR"
    chmod 700 "$MANAGED_KEYS_DIR"
    
    # Create key inventory file
    touch "$MANAGED_KEYS_DIR/key_inventory.json"
    chmod 600 "$MANAGED_KEYS_DIR/key_inventory.json"
}

# Add a new managed key
add_managed_key() {
    local username="$1"
    local pubkey="$2"
    local expiry="${3:-never}"
    
    local key_id=$(echo "$pubkey" | sha256sum | cut -d' ' -f1)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Add to inventory
    jq --arg kid "$key_id" \
       --arg user "$username" \
       --arg key "$pubkey" \
       --arg exp "$expiry" \
       --arg time "$timestamp" \
       '.keys[$kid] = {
           "username": $user,
           "public_key": $key,
           "expiry": $exp,
           "added_at": $time,
           "last_verified": $time
       }' "$MANAGED_KEYS_DIR/key_inventory.json" > "$MANAGED_KEYS_DIR/key_inventory.json.tmp"
    
    mv "$MANAGED_KEYS_DIR/key_inventory.json.tmp" "$MANAGED_KEYS_DIR/key_inventory.json"
    
    # Deploy key
    deploy_key "$username" "$pubkey"
}

# Deploy key to user account
deploy_key() {
    local username="$1"
    local pubkey="$2"
    
    local auth_keys="/home/$username/.ssh/authorized_keys"
    
    # Create .ssh directory if needed
    mkdir -p "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"
    
    # Add key
    echo "$pubkey" >> "$auth_keys"
    chmod 600 "$auth_keys"
    chown -R "$username:$username" "/home/$username/.ssh"
    
    logger -t ssh-key-management "Deployed key for user $username"
}

# Verify and clean expired keys
verify_keys() {
    local current_date=$(date +%s)
    
    jq -r '.keys[] | select(.expiry != "never") | 
           select(.expiry | strptime("%Y-%m-%d") | mktime < '$current_date') |
           .username + " " + .public_key' "$MANAGED_KEYS_DIR/key_inventory.json" |
    while read -r username key; do
        remove_key "$username" "$key"
    done
}

# Remove an expired or revoked key
remove_key() {
    local username="$1"
    local pubkey="$2"
    
    local auth_keys="/home/$username/.ssh/authorized_keys"
    
    if [ -f "$auth_keys" ]; then
        sed -i "\#$pubkey#d" "$auth_keys"
        logger -t ssh-key-management "Removed expired key for user $username"
    fi
}

# Sync keys across cluster
sync_keys() {
    while read -r node; do
        rsync -az --delete "$MANAGED_KEYS_DIR/" "root@$node:$MANAGED_KEYS_DIR/"
        ssh "root@$node" "systemctl restart ssh"
    done < "/etc/hardening/cluster_nodes"
}

# Monitor key changes
monitor_keys() {
    inotifywait -m -e modify,create,delete "$MANAGED_KEYS_DIR" |
    while read -r directory events filename; do
        if [[ "$filename" =~ key_inventory.json ]]; then
            logger -t ssh-key-management "Key inventory changed, syncing to cluster"
            sync_keys
        fi
    done
}

# Main key management process
main() {
    init_key_management
    
    # Run periodic verification
    while true; do
        verify_keys
        sleep 3600
    done &
    
    # Monitor for changes
    monitor_keys
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi