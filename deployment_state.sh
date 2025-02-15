#!/bin/bash

set -euo pipefail

STATE_DIR="/var/lib/hardening"
STATE_FILE="$STATE_DIR/deployment_state.json"
LOCK_FILE="$STATE_DIR/deployment.lock"

# Initialize state tracking
init_state() {
    mkdir -p "$STATE_DIR"
    
    # Check for existing lock
    if [ -f "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: Another deployment process is running (PID: $pid)"
            exit 1
        else
            # Clean up stale lock
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Create lock
    echo $$ > "$LOCK_FILE"
    
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << EOF
{
    "hostname": "$(hostname)",
    "last_deployment": null,
    "components": {},
    "status": "not_started",
    "version": "1.0.0",
    "errors": []
}
EOF
    fi
}

# Lock mechanism to prevent concurrent deployments
acquire_lock() {
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "Another deployment is in progress"
        exit 1
    fi
    trap 'rm -rf "$LOCK_FILE"' EXIT
}

# Update component state
update_component_state() {
    local component="$1"
    local status="$2"
    local timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    local temp_file=$(mktemp)
    jq --arg comp "$component" \
       --arg status "$status" \
       --arg time "$timestamp" \
       '.components[$comp] = {"status": $status, "updated_at": $time}' \
       "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

# Record deployment error
record_error() {
    local component="$1"
    local error_msg="$2"
    local timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    local temp_file=$(mktemp)
    jq --arg comp "$component" \
       --arg error "$error_msg" \
       --arg time "$timestamp" \
       '.errors += [{"component": $comp, "error": $error, "timestamp": $time}]' \
       "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

# Get deployment status
get_status() {
    jq -r '.status' "$STATE_FILE"
}

# Export state for monitoring
export_state() {
    local export_file="/var/log/hardening/deployment_$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "$(dirname "$export_file")"
    cp "$STATE_FILE" "$export_file"
    echo "Deployment state exported to $export_file"
}

# Main state tracking logic
track_deployment() {
    local component="$1"
    local cmd="$2"
    
    update_component_state "$component" "running"
    
    if ! eval "$cmd"; then
        update_component_state "$component" "failed"
        record_error "$component" "Command failed with exit code $?"
        return 1
    fi
    
    update_component_state "$component" "completed"
}

# Example usage in deployment:
# track_deployment "ssh_hardening" "bash scripts/sshdconfig"

# Set up cleanup trap
trap cleanup_state EXIT

cleanup_state() {
    # Clean up in case of interruption
    rm -f "$LOCK_FILE"
    if [ -f "$STATE_FILE" ]; then
        jq --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           --arg status "interrupted" \
           '.end_time = $time | .status = $status' \
           "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}