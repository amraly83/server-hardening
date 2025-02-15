#!/bin/bash

set -euo pipefail

SYNC_DIR="/var/lib/hardening/sync"
CLUSTER_NODES_FILE="/etc/hardening/cluster_nodes"

# Initialize sync directory
init_sync() {
    mkdir -p "$SYNC_DIR"
    touch "$CLUSTER_NODES_FILE"
}

# Add node to cluster
add_node() {
    local node="$1"
    if ! grep -q "^$node$" "$CLUSTER_NODES_FILE"; then
        echo "$node" >> "$CLUSTER_NODES_FILE"
    fi
}

# Sync state with other nodes
sync_state() {
    local my_hostname=$(hostname)
    
    while read -r node; do
        [ "$node" = "$my_hostname" ] && continue
        
        # Sync deployment state
        rsync -az --timeout=30 "$STATE_FILE" "root@$node:/var/lib/hardening/"
        
        # Sync security reports
        rsync -az --timeout=30 "/var/log/hardening/" "root@$node:/var/log/hardening/"
    done < "$CLUSTER_NODES_FILE"
}

# Check cluster health
check_cluster() {
    local unhealthy_nodes=()
    
    while read -r node; do
        if ! timeout 5 ssh -q "root@$node" "test -f /var/lib/hardening/deployment_state.json"; then
            unhealthy_nodes+=("$node")
        fi
    done < "$CLUSTER_NODES_FILE"
    
    if [ ${#unhealthy_nodes[@]} -gt 0 ]; then
        echo "Warning: Unhealthy nodes detected: ${unhealthy_nodes[*]}"
        return 1
    fi
}

# Verify cluster consistency
verify_cluster() {
    local inconsistent=0
    local base_state=$(jq -c '.components' "$STATE_FILE")
    
    while read -r node; do
        local node_state=$(ssh "root@$node" "jq -c '.components' /var/lib/hardening/deployment_state.json")
        if [ "$base_state" != "$node_state" ]; then
            echo "Warning: Node $node has inconsistent state"
            inconsistent=1
        fi
    done < "$CLUSTER_NODES_FILE"
    
    return $inconsistent
}

# Main cluster management function
manage_cluster() {
    init_sync
    
    # Register self in cluster
    add_node "$(hostname)"
    
    # Initial sync
    sync_state
    
    # Verify cluster health
    if ! check_cluster; then
        echo "ERROR: Cluster health check failed"
        return 1
    fi
    
    # Monitor cluster state
    while true; do
        sync_state
        verify_cluster
        sleep 300
    done
}

# Run cluster management if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    manage_cluster
fi