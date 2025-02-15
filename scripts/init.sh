#!/bin/bash

# Add workspace directory to PATH and set base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PATH="$BASE_DIR:$SCRIPT_DIR:$PATH"
export PATH

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Set up logging
setup_logging() {
    local log_dir="/var/log/hardening"
    mkdir -p "$log_dir"
    LOGFILE="$log_dir/deployment-$(hostname --short)-$(date +%y%m%d).log"
    DEBUG_LOG="$log_dir/debug-$(hostname --short)-$(date +%y%m%d).log"
    
    # Redirect all output to both console and log file
    exec 1> >(tee -a "$LOGFILE")
    exec 2> >(tee -a "$LOGFILE" >&2)
    
    # Start debug logging
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

# Set up logging first
setup_logging

# Initialize script environment
init_environment() {
    log "Initializing environment..."
    
    # Set required environment variables
    export DEBIAN_FRONTEND=noninteractive
    export SCRIPT_COUNT=0
    export BASE_DIR
    export SCRIPT_DIR
    
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
    
    # Initialize logging
    LOGFILE="/var/log/hardening/deployment-$(hostname --short)-$(date +%y%m%d).log"
    export LOGFILE
    
    # Source base configuration with absolute path
    if [ ! -f "$BASE_DIR/ubuntu.cfg" ]; then
        cp "$BASE_DIR/ubuntu.cfg.example" "$BASE_DIR/ubuntu.cfg"
        error "ubuntu.cfg not found. Created from example. Please configure it first."
    fi
    
    source "$BASE_DIR/ubuntu.cfg"
    source "$BASE_DIR/config/initpath.sh"
    
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
            # Check if file is a shell script regardless of extension
            if head -n1 "$script" | grep -q '^#!.*sh' || file "$script" | grep -q "shell script"; then
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
    
    # Initialize state tracking
    source "$SCRIPT_DIR/../deployment_state.sh"
    init_state
    
    log "Environment initialization complete"
}

# Run environment initialization
init_environment