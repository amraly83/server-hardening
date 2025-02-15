#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening/preflight.log"
REQUIRED_SPACE_GB=5
MIN_MEMORY_MB=1024
REQUIRED_SERVICES=("sshd" "systemd-journald" "systemd-timesyncd")
CRITICAL_DIRS=("/etc/ssh" "/etc/pam.d" "/etc/security" "/var/log")

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

    # Check CPU cores
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        echo "WARNING: Less than 2 CPU cores available. Performance may be impacted."
    fi
}

verify_critical_paths() {
    local errors=0
    
    # Check critical directories
    for dir in "${CRITICAL_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "ERROR: Critical directory missing: $dir"
            errors=$((errors + 1))
        fi
    done
    
    # Verify permissions on critical paths
    if [ -d "/etc/ssh" ]; then
        local ssh_perms=$(stat -c "%a" /etc/ssh)
        if [ "$ssh_perms" != "755" ]; then
            echo "ERROR: Incorrect permissions on /etc/ssh. Expected 755, got $ssh_perms"
            errors=$((errors + 1))
        fi
    fi
    
    return "$errors"
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

verify_backup_state() {
    # Check if backup directory exists
    local backup_dir="/var/backups/hardening"
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi
    
    # Verify backup directory permissions
    local backup_perms=$(stat -c "%a" "$backup_dir")
    if [ "$backup_perms" != "750" ]; then
        chmod 750 "$backup_dir"
    fi
    
    # Create initial backup if needed
    if ! find "$backup_dir" -maxdepth 1 -name "pre_hardening_*" | grep -q .; then
        echo "Creating initial system backup..."
        tar czf "$backup_dir/pre_hardening_$(date +%Y%m%d_%H%M%S).tar.gz" \
            /etc/ssh /etc/pam.d /etc/security /etc/audit \
            /etc/systemd/system /etc/ufw 2>/dev/null || true
    fi
}

check_network_config() {
    # Verify network connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "ERROR: No internet connectivity"
        return 1
    fi

    # Check DNS resolution
    if ! host -W 5 ubuntu.com >/dev/null 2>&1; then
        echo "ERROR: DNS resolution not working"
        return 1
    fi
    
    # Check if SSH is accessible on non-standard port if configured
    if [ -n "${SSH_PORT:-}" ] && [ "$SSH_PORT" != "22" ]; then
        if ! netstat -ln | grep -q ":${SSH_PORT}.*LISTEN"; then
            echo "WARNING: SSH not listening on configured port $SSH_PORT"
        fi
    fi
}

verify_system_state() {
    # Check for existing hardening
    if [ -f "/var/lib/hardening/deployed" ]; then
        echo "WARNING: System appears to be already hardened. Running hardening again may cause issues."
        return 1
    fi
    
    # Check system load
    local load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1)
    if [ "$(echo "$load > 2.0" | bc)" -eq 1 ]; then
        echo "WARNING: System load is high: $load"
    fi
    
    # Check for pending updates
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get --simulate upgrade 2>&1 | grep -q '^Inst'; then
            echo "WARNING: System has pending updates"
        fi
    fi
}

cleanup_on_failure() {
    echo "Pre-flight checks failed. Cleaning up..."
    # Add any necessary cleanup steps here
}

main() {
    echo "Starting pre-flight checks at $(date)" | tee -a "$LOGFILE"
    
    local checks=(
        "check_system_resources"
        "verify_critical_paths"
        "check_running_services"
        "verify_backup_state"
        "check_network_config"
        "verify_system_state"
    )
    
    local failed=0
    for check in "${checks[@]}"; do
        echo "Running check: $check" | tee -a "$LOGFILE"
        if ! $check 2>&1 | tee -a "$LOGFILE"; then
            failed=$((failed + 1))
            echo "Check failed: $check" | tee -a "$LOGFILE"
        fi
    done
    
    if [ $failed -gt 0 ]; then
        echo "ERROR: $failed pre-flight checks failed. See $LOGFILE for details."
        cleanup_on_failure
        exit 1
    fi
    
    echo "All pre-flight checks passed successfully" | tee -a "$LOGFILE"
}

# Run main function
main "$@"