#!/bin/bash

set -euo pipefail

# Status endpoint configuration
METRICS_PORT=9100
STATUS_FILE="/var/lib/hardening/status.json"
ALERT_THRESHOLDS="/etc/hardening/alert_thresholds.json"

generate_status_metrics() {
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "metrics": {
        "ssh_attempts": $(grep "Failed password" /var/log/auth.log | wc -l),
        "firewall_blocks": $(grep "UFW BLOCK" /var/log/ufw.log | wc -l),
        "file_integrity_alerts": $(find /var/log/aide/ -type f -mtime -1 -exec grep -l "changed" {} \; | wc -l),
        "system_users": $(cut -d: -f1 /etc/passwd | wc -l),
        "active_connections": $(netstat -ant | grep ESTABLISHED | wc -l),
        "disk_usage": $(df / --output=pcent | tail -n1 | tr -d ' %'),
        "memory_usage": $(free | grep Mem | awk '{print int($3/$2 * 100)}'),
        "load_average": $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    },
    "components": {
        "sshd": "$(systemctl is-active sshd)",
        "fail2ban": "$(systemctl is-active fail2ban)",
        "auditd": "$(systemctl is-active auditd)",
        "aide": "$(systemctl is-active aidecheck.timer)",
        "ufw": "$(systemctl is-active ufw)"
    },
    "last_backup": "$(stat -c %Y /var/backups/hardening/$(ls -t /var/backups/hardening/ | head -n1))",
    "config_hash": "$(find /etc/hardening -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)"
}
EOF
}

check_thresholds() {
    local alerts=()
    
    # Load thresholds
    local disk_threshold=$(jq -r '.thresholds.disk_usage' "$ALERT_THRESHOLDS")
    local memory_threshold=$(jq -r '.thresholds.memory_usage' "$ALERT_THRESHOLDS")
    local load_threshold=$(jq -r '.thresholds.load_average' "$ALERT_THRESHOLDS")
    
    # Check current values against thresholds
    local disk_usage=$(jq -r '.metrics.disk_usage' "$STATUS_FILE")
    local memory_usage=$(jq -r '.metrics.memory_usage' "$STATUS_FILE")
    local load_average=$(jq -r '.metrics.load_average' "$STATUS_FILE")
    
    if [ "$disk_usage" -gt "$disk_threshold" ]; then
        alerts+=("Disk usage above threshold: ${disk_usage}%")
    fi
    
    if [ "$memory_usage" -gt "$memory_threshold" ]; then
        alerts+=("Memory usage above threshold: ${memory_usage}%")
    fi
    
    if (( $(echo "$load_average > $load_threshold" | bc -l) )); then
        alerts+=("Load average above threshold: $load_average")
    fi
    
    # Check component status
    while IFS= read -r component; do
        local status=$(jq -r ".components.\"$component\"" "$STATUS_FILE")
        if [ "$status" != "active" ]; then
            alerts+=("Component $component is $status")
        fi
    done < <(jq -r '.components | keys[]' "$STATUS_FILE")
    
    # Send alerts if any
    if [ ${#alerts[@]} -gt 0 ]; then
        {
            echo "Security Alert - $(hostname)"
            echo "Time: $(date)"
            printf '%s\n' "${alerts[@]}"
        } | mail -s "Security Alert - $(hostname)" "$ADMINEMAIL"
    fi
}

start_metrics_server() {
    # Simple metrics endpoint using netcat
    while true; do
        generate_status_metrics
        check_thresholds
        echo -e "HTTP/1.1 200 OK\n\n$(cat $STATUS_FILE)" | nc -l -p $METRICS_PORT
        sleep 60
    done
}

# Initialize
mkdir -p "$(dirname "$STATUS_FILE")"
start_metrics_server