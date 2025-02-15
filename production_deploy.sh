#!/bin/bash

# Add workspace directory to PATH and set script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIG_DIR="$SCRIPT_DIR/config"

# Install required packages first, before any other operations
install_dependencies() {
    echo "Installing required packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y jq net-tools mailutils file
}

# Run initial package installation
install_dependencies

# Enable debug output temporarily
set -x

# Ensure script permissions
chmod +x "$SCRIPTS_DIR"/*

# Source initialization script with absolute path
source "$SCRIPTS_DIR/init.sh"

# List available functions for debugging
echo "Available hardening functions:"
declare -F | grep '^declare -f f_' || true

# Disable debug output
set +x

# Pre-deployment checks
pre_deployment_check() {
    log "Running pre-deployment checks..."
    cd "$SCRIPT_DIR" || exit 1
    
    # Check system requirements
    if ! command -v systemctl &> /dev/null; then
        error "systemd is required but not installed"
    fi
    
    # Check disk space
    local available_space=$(df -P / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then # 5GB in KB
        error "Insufficient disk space. At least 5GB required"
    fi
    
    # Check Ubuntu version
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 22.04"; then
        warn "This script is tested on Ubuntu 22.04. Other versions may not work correctly"
    fi
}

# Main deployment function
deploy_hardening() {
    log "Starting hardening deployment..."
    cd "$SCRIPT_DIR" || exit 1
    
    # Component deployment with state tracking
    local components=(
        "kernel:f_kernel"
        "network:f_network_isolation"
        "ssh:f_sshdconfig"
        "auth:f_password"
        "mfa:f_mfa_config"
        "monitoring:f_security_monitoring"
        "containers:f_container_security"
        "audit:f_auditd"
        "integrity:f_aide"
    )
    
    for component in "${components[@]}"; do
        local name="${component%%:*}"
        local func="${component#*:}"
        
        log "Deploying component: $name"
        if ! declare -F "$func" > /dev/null; then
            warn "Function $func not found, skipping component $name"
            continue
        fi
        
        if ! track_deployment "$name" "$func"; then
            warn "Component $name failed"
            if [[ "$name" == "ssh" ]] || [[ "$name" == "auth" ]] || [[ "$name" == "network" ]]; then
                error "Critical component failed, aborting deployment"
            fi
        fi
    done
    
    # Export final state
    export_state
}

# Main execution
main() {
    log "Starting production deployment..."
    cd "$SCRIPT_DIR" || exit 1
    
    # Run deployment steps
    pre_deployment_check
    deploy_hardening
    
    if [ -n "$ADMINEMAIL" ]; then
        {
            echo "Hardening deployment completed on $(hostname)"
            echo "Deployment state:"
            cat "$STATE_FILE"
            echo "See attached logs for details."
        } | mail -s "Server Hardening Complete - $(hostname)" -a "$LOGFILE" "$ADMINEMAIL"
    fi
    
    log "Deployment process completed. System should be rebooted for changes to take effect."
}

main "$@"