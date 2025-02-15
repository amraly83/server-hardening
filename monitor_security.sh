#!/bin/bash

set -euo pipefail

LOGFILE="/var/log/hardening-monitor.log"
ALERT_EMAIL="${ADMINEMAIL:-root@localhost}"

check_security_services() {
    local services=(
        "sshd"
        "fail2ban"
        "auditd"
        "aide"
        "apparmor"
        "ufw"
        "rkhunter"
        "ossec-hids"
    )
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            echo "CRITICAL: $service is not running"
            return 1
        fi
    done
}

check_file_integrity() {
    # Run AIDE check
    if ! aide --check; then
        echo "CRITICAL: File integrity check failed"
        return 1
    fi
}

check_open_ports() {
    # Only allow specified ports
    local allowed_ports=("$SSH_PORT" "80" "443")
    local open_ports=$(netstat -tuln | grep 'LISTEN' | awk '{print $4}' | awk -F: '{print $NF}')
    
    for port in $open_ports; do
        if [[ ! " ${allowed_ports[@]} " =~ " ${port} " ]]; then
            echo "WARNING: Unexpected open port: $port"
        fi
    done
}

check_failed_logins() {
    # Check for suspicious login attempts
    local failed_count=$(grep "Failed password" /var/log/auth.log | wc -l)
    if [ "$failed_count" -gt 100 ]; then
        echo "WARNING: High number of failed login attempts: $failed_count"
    fi
}

check_disk_encryption() {
    # Verify disk encryption status
    if ! cryptsetup status root 2>/dev/null; then
        echo "WARNING: Root filesystem encryption not detected"
    fi
}

monitor_security() {
    local status=0
    local report=""
    
    # Run all checks
    report+="=== Security Monitor Report ===\n"
    report+="Date: $(date)\n"
    report+="Host: $(hostname)\n\n"
    
    if ! check_security_services; then
        report+="[FAIL] Security services check\n"
        status=1
    else
        report+="[PASS] Security services check\n"
    fi
    
    if ! check_file_integrity; then
        report+="[FAIL] File integrity check\n"
        status=1
    else
        report+="[PASS] File integrity check\n"
    fi
    
    # Run other checks and append to report
    check_open_ports >> "$LOGFILE"
    check_failed_logins >> "$LOGFILE"
    check_disk_encryption >> "$LOGFILE"
    
    # Send report
    echo -e "$report" | tee -a "$LOGFILE"
    
    if [ $status -ne 0 ]; then
        echo -e "$report" | mail -s "Security Alert - $(hostname)" "$ALERT_EMAIL"
    fi
    
    return $status
}

# Run monitor
monitor_security