#!/bin/bash

set -euo pipefail

# Status endpoint configuration
METRICS_PORT=9100
STATUS_FILE="/var/lib/hardening/status.json"
ALERT_THRESHOLDS="/etc/hardening/alert_thresholds.json"

generate_status_metrics() {
    # Initialize values with safe defaults
    local ssh_attempts=0
    local fw_blocks=0
    local integrity_alerts=0
    local active_conns=0
    local disk_usage=0
    local mem_usage=0
    local load_avg=0

    # Safely collect metrics
    [[ -f /var/log/auth.log ]] && ssh_attempts=$(grep -c "Failed password" /var/log/auth.log || echo 0)
    [[ -f /var/log/ufw.log ]] && fw_blocks=$(grep -c "UFW BLOCK" /var/log/ufw.log || echo 0)
    [[ -d /var/log/aide ]] && integrity_alerts=$(find /var/log/aide/ -type f -mtime -1 -exec grep -l "changed" {} \; 2>/dev/null | wc -l || echo 0)
    active_conns=$(netstat -ant 2>/dev/null | grep -c ESTABLISHED || echo 0)
    disk_usage=$(df / --output=pcent 2>/dev/null | tail -n1 | tr -d ' %' || echo 0)
    mem_usage=$(free 2>/dev/null | grep Mem | awk '{print int($3/$2 * 100)}' || echo 0)
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo 0)

    # Create status file directory if it doesn't exist
    mkdir -p "$(dirname "$STATUS_FILE")"

    # Generate JSON with proper integer values
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "metrics": {
        "ssh_attempts": ${ssh_attempts:-0},
        "firewall_blocks": ${fw_blocks:-0},
        "file_integrity_alerts": ${integrity_alerts:-0},
        "active_connections": ${active_conns:-0},
        "disk_usage": ${disk_usage:-0},
        "memory_usage": ${mem_usage:-0},
        "load_average": ${load_avg:-0}
    },
    "components": {
        "sshd": "$(systemctl is-active sshd 2>/dev/null || echo unknown)",
        "fail2ban": "$(systemctl is-active fail2ban 2>/dev/null || echo unknown)",
        "auditd": "$(systemctl is-active auditd 2>/dev/null || echo unknown)",
        "aide": "$(systemctl is-active aidecheck.timer 2>/dev/null || echo unknown)",
        "ufw": "$(systemctl is-active ufw 2>/dev/null || echo unknown)"
    }
}
EOF
}

# Check thresholds and generate alerts
check_thresholds() {
    if [[ -f "$STATUS_FILE" && -f "$ALERT_THRESHOLDS" ]]; then
        local current_metrics
        local thresholds
        current_metrics=$(jq -r '.metrics' "$STATUS_FILE")
        thresholds=$(jq -r '.' "$ALERT_THRESHOLDS")

        for metric in $(jq -r 'keys[]' <<< "$current_metrics"); do
            local value
            local threshold
            value=$(jq -r ".$metric" <<< "$current_metrics")
            threshold=$(jq -r ".$metric // 0" <<< "$thresholds")

            if [[ -n "$value" && -n "$threshold" ]] && ((value > threshold)); then
                logger -p auth.warning -t hardening-monitor "Alert: $metric exceeded threshold ($value > $threshold)"
            fi
        done
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