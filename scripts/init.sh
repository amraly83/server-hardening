#!/bin/bash

# DO NOT modify PATH here, let initpath.sh handle it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Set up logging with cleaner debug output
setup_logging() {
    local log_dir="/var/log/hardening"
    mkdir -p "$log_dir"
    LOGFILE="$log_dir/deployment-$(hostname --short)-$(date +%y%m%d).log"
    DEBUG_LOG="$log_dir/debug-$(hostname --short)-$(date +%y%m%d).log"
    
    # Configure debug output format
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    
    # Redirect output while preserving debug format
    exec 1> >(tee -a "$LOGFILE")
    exec 2> >(tee -a "$LOGFILE" >&2)
    
    echo "=== Debug Log Started $(date) ===" > "$DEBUG_LOG"
    set -x
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" 
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" 
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" 
    exit 1
}

# Initialize script environment
init_environment() {
    log "Initializing environment..."
    
    # Source base configuration first
    if [ ! -f "$BASE_DIR/ubuntu.cfg" ]; then
        cp "$BASE_DIR/ubuntu.cfg.example" "$BASE_DIR/ubuntu.cfg"
        error "ubuntu.cfg not found. Created from example. Please configure it first."
    fi
    
    # Source configs in correct order
    source "$BASE_DIR/ubuntu.cfg"
    source "$BASE_DIR/config/initpath.sh"
    
    # Now set environment variables after paths are configured
    export DEBIAN_FRONTEND=noninteractive
    export SCRIPT_COUNT=0
    
    # Create required directories
    local dirs=(
        "/var/log/hardening"
        "/var/lib/hardening"
        "/etc/hardening"
        "/var/log/aide"
        "/var/backups/hardening"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 750 "$dir"
    done
    
    # Install dependencies after paths are set
    log "Installing required packages..."
    apt-get update
    apt-get install -y jq net-tools mailutils file
    
    # Source all script functions
    log "Sourcing script functions..."
    
    # First source the pre script as it contains base functions
    if [[ -f "$SCRIPT_DIR/pre" ]]; then
        source "$SCRIPT_DIR/pre"
        log "Sourced: pre"
    else
        error "Required script 'pre' not found"
    fi
    
    # Then source all other scripts
    while IFS= read -r -d '' script; do
        if [[ "$script" != *"/pre" ]] && [[ -f "$script" ]]; then
            # Source any script that doesn't have an extension or is a shell script
            if [[ "$script" != *.* ]] || grep -q '^#!/.*sh' "$script" 2>/dev/null; then
                source "$script"
                log "Sourced: $script"
            fi
        fi
    done < <(find "$SCRIPT_DIR" -type f -print0)
    
    # Verify required functions are available
    local required_functions=(
        "f_kernel"
        "f_network_isolation"
        "f_sshdconfig"
        "f_password"
        "f_mfa_config"
        "f_security_monitoring"
        "f_container_security"
        "f_auditd"
        "f_aide"
    )
    
    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! declare -F "$func" > /dev/null; then
            missing_functions+=("$func")
        fi
    done
    
    if (( ${#missing_functions[@]} > 0 )); then
        error "Required functions not found: ${missing_functions[*]}"
    fi
    
    # Initialize state tracking last
    source "$BASE_DIR/deployment_state.sh"
    init_state
    
    log "Environment initialization complete"
}

# Set up logging first
setup_logging

# Then initialize environment 
init_environment