#!/bin/bash

set -euo pipefail

STATE_DIR="/var/lib/hardening"
BACKUP_DIR="/var/backups/hardening"
ROLLBACK_LOG="/var/log/hardening/rollback.log"

# State tracking for rollback points
declare -A ROLLBACK_POINTS=(
    ["pre_hardening"]="Initial system state"
    ["post_ssh"]="After SSH hardening"
    ["post_firewall"]="After firewall configuration"
    ["post_audit"]="After audit setup"
    ["post_monitoring"]="After monitoring setup"
    ["complete"]="Full deployment complete"
)

create_rollback_point() {
    local point_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local point_dir="$BACKUP_DIR/rollback_${point_name}_${timestamp}"
    
    echo "Creating rollback point: $point_name" | tee -a "$ROLLBACK_LOG"
    
    # Create backup directory
    mkdir -p "$point_dir"
    
    # Backup critical configurations
    tar czf "$point_dir/etc_backup.tar.gz" \
        /etc/ssh \
        /etc/pam.d \
        /etc/security \
        /etc/audit \
        /etc/ufw \
        /etc/systemd/system
        
    # Save service states
    systemctl list-units --state=active,failed > "$point_dir/service_state.txt"
    
    # Save iptables rules
    iptables-save > "$point_dir/iptables.rules"
    
    # Save current state metadata
    cat > "$point_dir/metadata.json" << EOF
{
    "point_name": "$point_name",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "description": "${ROLLBACK_POINTS[$point_name]}",
    "system_info": {
        "kernel": "$(uname -r)",
        "hostname": "$(hostname)",
        "uptime": "$(uptime -p)"
    }
}
EOF
    
    # Update current rollback point symlink
    ln -sf "$point_dir" "$STATE_DIR/current_rollback"
    
    echo "Rollback point created at $point_dir" | tee -a "$ROLLBACK_LOG"
}

perform_rollback() {
    local point_name="$1"
    local target_backup
    
    echo "Initiating rollback to point: $point_name" | tee -a "$ROLLBACK_LOG"
    
    # Find most recent backup for given point
    target_backup=$(find "$BACKUP_DIR" -maxdepth 1 -name "rollback_${point_name}_*" | sort -r | head -n1)
    
    if [ -z "$target_backup" ]; then
        echo "ERROR: No rollback point found for $point_name" | tee -a "$ROLLBACK_LOG"
        return 1
    fi
    
    # Stop affected services
    systemctl stop sshd fail2ban auditd || true
    
    # Restore configurations
    cd /
    tar xzf "$target_backup/etc_backup.tar.gz"
    
    # Restore firewall rules
    iptables-restore < "$target_backup/iptables.rules"
    
    # Restart services
    systemctl daemon-reload
    systemctl restart sshd fail2ban auditd
    
    echo "Rollback completed successfully" | tee -a "$ROLLBACK_LOG"
    
    # Verify critical services
    local failed_services=()
    while read -r service; do
        if ! systemctl is-active --quiet "$service"; then
            failed_services+=("$service")
        fi
    done < <(grep "\.service" "$target_backup/service_state.txt" | awk '{print $1}')
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        echo "WARNING: Some services failed to restart: ${failed_services[*]}" | tee -a "$ROLLBACK_LOG"
        return 1
    fi
}

cleanup_old_rollbacks() {
    # Keep only last 3 rollbacks per point
    for point in "${!ROLLBACK_POINTS[@]}"; do
        find "$BACKUP_DIR" -maxdepth 1 -name "rollback_${point}_*" | sort -r | tail -n +4 | xargs -r rm -rf
    done
}

# Main execution
main() {
    local command="$1"
    local point_name="${2:-}"
    
    case "$command" in
        create)
            if [ -z "$point_name" ] || [ -z "${ROLLBACK_POINTS[$point_name]:-}" ]; then
                echo "ERROR: Invalid rollback point name"
                exit 1
            fi
            create_rollback_point "$point_name"
            cleanup_old_rollbacks
            ;;
        rollback)
            if [ -z "$point_name" ] || [ -z "${ROLLBACK_POINTS[$point_name]:-}" ]; then
                echo "ERROR: Invalid rollback point name"
                exit 1
            fi
            perform_rollback "$point_name"
            ;;
        list)
            find "$BACKUP_DIR" -maxdepth 1 -name "rollback_*" -type d | sort -r | \
                while read -r backup; do
                    jq -r '"Point: \(.point_name)\nTime: \(.timestamp)\nDescription: \(.description)"' \
                        "$backup/metadata.json"
                    echo "---"
                done
            ;;
        *)
            echo "Usage: $0 {create|rollback|list} [point_name]"
            exit 1
            ;;
    esac
}

main "$@"