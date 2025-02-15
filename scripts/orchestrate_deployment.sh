#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="/var/log/hardening"
DEPLOYMENT_LOG="$LOG_DIR/deployment.log"
BACKUP_DIR="/var/backups/hardening"

# Ensure proper script ordering
declare -A DEPLOYMENT_SEQUENCE
DEPLOYMENT_SEQUENCE=(
    ["1_init"]="init.sh"
    ["2_verify"]="pre-flight-check.sh"
    ["3_backup"]="rollback_manager.sh create_rollback_point pre_hardening"
    ["4_network"]="network_isolation"
    ["5_ssh"]="verify_ssh.sh sshdconfig"
    ["6_auth"]="password mfa"
    ["7_audit"]="auditd"
    ["8_monitoring"]="security_monitoring"
    ["9_verify"]="integration_tests.sh"
)

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$DEPLOYMENT_LOG"
}

verify_prerequisites() {
    # Check root privileges
    if [ "$EUID" -ne 0 ]; then
        log_message "This script must be run as root" "ERROR"
        exit 1
    fi

    # Create required directories
    for dir in "$LOG_DIR" "$BACKUP_DIR"; do
        if ! mkdir -p "$dir"; then
            log_message "Failed to create directory: $dir" "ERROR"
            exit 1
        fi
        chmod 750 "$dir"
    done
}

run_deployment_sequence() {
    local last_successful_stage=""
    
    for stage in "${!DEPLOYMENT_SEQUENCE[@]}"; do
        log_message "Starting stage: $stage" "INFO"
        
        # Split components by space instead of colon
        IFS=' ' read -ra components <<< "${DEPLOYMENT_SEQUENCE[$stage]}"
        
        for component in "${components[@]}"; do
            log_message "Running component: $component" "INFO"
            
            if ! bash "$SCRIPT_DIR/$component"; then
                log_message "Failed at stage $stage, component $component" "ERROR"
                if [[ $stage =~ ^[45] ]]; then  # Critical stages (network and SSH)
                    log_message "Critical component failed, initiating rollback" "ERROR"
                    if ! bash "$SCRIPT_DIR/rollback_manager.sh" "$last_successful_stage"; then
                        log_message "Rollback failed" "ERROR"
                    fi
                    exit 1
                fi
                return 1
            fi
        done
        
        last_successful_stage=$stage
        log_message "Stage $stage completed successfully" "INFO"
    done
    
    return 0
}

main() {
    verify_prerequisites
    
    log_message "Starting hardening deployment"
    
    if ! run_deployment_sequence; then
        log_message "Deployment failed" "ERROR"
        exit 1
    fi
    
    log_message "Deployment completed successfully" "SUCCESS"
}

# Execute main function with error handling
if ! main "$@"; then
    log_message "Script failed" "ERROR"
    exit 1
fi