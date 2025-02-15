#!/bin/bash

set -euo pipefail

# Source all script functions
for script in ./scripts/*; do
    if [[ -f "$script" ]]; then
        source "$script"
    fi
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log file
LOGFILE="deployment-$(hostname --short)-$(date +%y%m%d).log"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOGFILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOGFILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOGFILE"
}

# Validation functions
validate_config() {
    log "Validating configuration..."
    
    # Required variables
    local required_vars=(ADMIN_USER ADMIN_PASSWORD SSH_PORT ADMINEMAIL)
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "$var must be set in ubuntu.cfg"
        fi
    done
    
    # Validate SSH port
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
        error "SSH_PORT must be a valid port number (1024-65535)"
    fi
}

# Pre-deployment checks
pre_deployment_check() {
    log "Running pre-deployment checks..."
    
    # Install required packages
    if ! command -v jq &> /dev/null; then
        log "Installing required package: jq"
        apt-get update && apt-get install -y jq
    fi
    
    # Check system requirements
    if ! command -v systemctl &> /dev/null; then
        error "systemd is required but not installed"
    fi
    
    # Check disk space
    local available_space=$(df -P / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then # 5GB in KB
        error "Insufficient disk space. At least 5GB required"
    fi
    
    # Verify running as root
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
    fi
    
    # Check Ubuntu version
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 22.04"; then
        warn "This script is tested on Ubuntu 22.04. Other versions may not work correctly"
    fi
}

# Backup critical files
backup_critical_files() {
    log "Creating backups of critical files..."
    
    local backup_dir="/root/hardening_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # List of critical files to backup
    local critical_files=(
        "/etc/ssh/sshd_config"
        "/etc/pam.d/common-auth"
        "/etc/pam.d/common-password"
        "/etc/login.defs"
        "/etc/sysctl.conf"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            cp -p "$file" "$backup_dir/$(basename "$file")"
        fi
    done
    
    log "Backups created in $backup_dir"
}

# Source state management
source ./deployment_state.sh

# Main deployment function
deploy_hardening() {
    log "Starting hardening deployment..."
    
    # Initialize state tracking
    init_state
    acquire_lock
    
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
        if ! track_deployment "$name" "$func"; then
            warn "Component $name failed"
            if [[ "$name" == "ssh" ]] || [[ "$name" == "auth" ]] || [[ "$name" == "network" ]]; then
                error "Critical component failed, aborting deployment"
            fi
        fi
    done
    
    # Run integration tests
    if ! bash ./integration_tests.sh; then
        record_error "integration_tests" "Integration tests failed"
        error "Integration tests failed, see logs for details"
    fi
    
    # Export final state
    export_state
    
    # Start monitoring
    log "Starting security monitoring..."
    if ! systemctl start hardening-monitor.service; then
        warn "Failed to start monitoring service"
    fi
}

# Post-deployment validation
validate_deployment() {
    log "Running post-deployment validation..."
    
    # Check critical services
    local services=(sshd fail2ban auditd aide ufw)
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            warn "Service $service is not running"
        fi
    done
    
    # Verify SSH configuration
    if ! sshd -t; then
        error "SSH configuration is invalid"
    fi
    
    # Test firewall
    if ! ufw status | grep -q "active"; then
        warn "Firewall is not active"
    fi
}

# Main execution
main() {
    log "Starting production deployment..."
    
    # Source configuration
    if [ ! -f "./ubuntu.cfg" ]; then
        error "Configuration file ubuntu.cfg not found"
    fi
    source ./ubuntu.cfg
    
    # Source all script functions first
    for script in ./scripts/*; do
        if [[ -f "$script" ]]; then
            source "$script"
        fi
    done
    
    # Source state management after functions
    source ./deployment_state.sh
    
    # Verify system state before proceeding
    if [ "$(get_status)" = "in_progress" ]; then
        error "Another deployment appears to be in progress"
    fi
    
    # Run deployment steps
    pre_deployment_check
    validate_config
    backup_critical_files
    deploy_hardening
    
    if [ -n "$ADMINEMAIL" ]; then
        # Send detailed report including state export
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