#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/preflight.log"
REQUIRED_SPACE_GB=5
MIN_MEMORY_MB=1024
REQUIRED_SERVICES=("sshd" "systemd-journald" "systemd-timesyncd")

check_system_resources() {
    # Check disk space
    local available_space_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    if [ "${available_space_gb%.*}" -lt "$REQUIRED_SPACE_GB" ]; then
        echo "ERROR: Insufficient disk space. Required: ${REQUIRED_SPACE_GB}GB, Available: ${available_space_gb}GB"
        return 1
    fi
    
    # Check memory
    local available_memory_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if [ "$available_memory_mb" -lt "$MIN_MEMORY_MB" ]; then
        echo "ERROR: Insufficient memory. Required: ${MIN_MEMORY_MB}MB, Available: ${available_memory_mb}MB"
        return 1
    fi
}

check_running_services() {
    local failed_services=()
    
    for service in "${REQUIRED_SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        echo "ERROR: Required services not running: ${failed_services[*]}"
        return 1
    fi
}

check_network() {
    # Verify network connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        echo "ERROR: No internet connectivity"
        return 1
    fi
    
    # Check DNS resolution
    if ! host -t A ubuntu.com &>/dev/null; then
        echo "ERROR: DNS resolution not working"
        return 1
    }
}

verify_backup_state() {
    # Check if backup exists
    local backup_path="/var/backups/hardening/$(date +%Y%m%d)"
    if [ ! -d "$backup_path" ]; then
        echo "Creating initial backup..."
        /opt/hardening/backup-security-config.sh
    fi
}

check_process_conflicts() {
    # Check for processes that might interfere
    local conflict_processes=("aide" "tripwire" "fail2ban-server" "auditd")
    local running_conflicts=()
    
    for proc in "${conflict_processes[@]}"; do
        if pgrep -f "$proc" >/dev/null; then
            running_conflicts+=("$proc")
        fi
    done
    
    if [ ${#running_conflicts[@]} -gt 0 ]; then
        echo "WARNING: Potentially conflicting processes running: ${running_conflicts[*]}"
    fi
}

main() {
    echo "Starting pre-flight checks at $(date)" | tee -a "$LOGFILE"
    
    local checks=(
        "check_system_resources"
        "check_running_services"
        "check_network"
        "verify_backup_state"
        "check_process_conflicts"
    )
    
    for check in "${checks[@]}"; do
        echo "Running $check..." | tee -a "$LOGFILE"
        if ! $check 2>&1 | tee -a "$LOGFILE"; then
            echo "Pre-flight check failed: $check" | tee -a "$LOGFILE"
            exit 1
        fi
    done
    
    echo "All pre-flight checks passed successfully" | tee -a "$LOGFILE"
}

main "$@"