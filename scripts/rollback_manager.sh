#!/bin/bash

set -euo pipefail

STATE_DIR="/var/lib/hardening"
BACKUP_DIR="/var/backups/hardening"
ROLLBACK_LOG="/var/log/hardening/rollback.log"

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$ROLLBACK_LOG"
}

ensure_dirs() {
    for dir in "$STATE_DIR" "$BACKUP_DIR" "$(dirname "$ROLLBACK_LOG")"; do
        if ! mkdir -p "$dir"; then
            echo "Failed to create directory: $dir" >&2
            return 1
        fi
        chmod 750 "$dir"
    done
}

create_rollback_point() {
    local point_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local point_dir="$BACKUP_DIR/rollback_${point_name}_${timestamp}"
    
    log_message "Creating rollback point: $point_name" "INFO"
    
    ensure_dirs
    
    # Create backup directory
    mkdir -p "$point_dir"
    
    # Backup critical configurations based on stage
    case "$point_name" in
        "4_users")
            tar czf "$point_dir/users_backup.tar.gz" \
                /etc/passwd /etc/shadow /etc/group /etc/gshadow \
                /etc/sudoers /etc/sudoers.d 2>/dev/null || true
            ;;
        "5_network")
            tar czf "$point_dir/network_backup.tar.gz" \
                /etc/netplan /etc/network /etc/hosts /etc/resolv.conf \
                /etc/ufw 2>/dev/null || true
            ;;
        "6_ssh")
            tar czf "$point_dir/ssh_backup.tar.gz" \
                /etc/ssh /root/.ssh /home/*/.ssh 2>/dev/null || true
            ;;
        "7_auth")
            tar czf "$point_dir/auth_backup.tar.gz" \
                /etc/pam.d /etc/security /etc/login.defs \
                /etc/fail2ban 2>/dev/null || true
            ;;
        "8_audit")
            tar czf "$point_dir/audit_backup.tar.gz" \
                /etc/audit /etc/default/auditd \
                /etc/systemd/system/auditd.service.d 2>/dev/null || true
            ;;
        "9_monitoring")
            tar czf "$point_dir/monitoring_backup.tar.gz" \
                /etc/logrotate.d /etc/rsyslog.d /etc/aide \
                /etc/rkhunter.conf 2>/dev/null || true
            ;;
        *)
            tar czf "$point_dir/full_backup.tar.gz" \
                /etc/ssh /etc/pam.d /etc/security /etc/audit \
                /etc/systemd/system /etc/ufw 2>/dev/null || true
            ;;
    esac
    
    # Record state metadata
    cat > "$point_dir/metadata.json" << EOF
{
    "point_name": "$point_name",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "stage": "$point_name"
}
EOF

    log_message "Rollback point created: $point_dir" "SUCCESS"
}

rollback() {
    local target_stage="$1"
    local latest_backup
    
    log_message "Initiating rollback to stage: $target_stage" "INFO"
    
    # Find latest backup for the target stage
    latest_backup=$(find "$BACKUP_DIR" -name "rollback_${target_stage}_*" -type d -print0 | xargs -0 ls -td | head -n1)
    
    if [ -z "$latest_backup" ]; then
        log_message "No backup found for stage $target_stage" "ERROR"
        return 1
    fi
    
    # Extract backup based on stage
    case "$target_stage" in
        "4_users")
            tar xzf "$latest_backup/users_backup.tar.gz" -C / 2>/dev/null || true
            ;;
        "5_network")
            tar xzf "$latest_backup/network_backup.tar.gz" -C / 2>/dev/null || true
            systemctl restart networking ufw
            ;;
        "6_ssh")
            tar xzf "$latest_backup/ssh_backup.tar.gz" -C / 2>/dev/null || true
            systemctl restart sshd
            ;;
        "7_auth")
            tar xzf "$latest_backup/auth_backup.tar.gz" -C / 2>/dev/null || true
            systemctl restart fail2ban
            ;;
        "8_audit")
            tar xzf "$latest_backup/audit_backup.tar.gz" -C / 2>/dev/null || true
            systemctl restart auditd
            ;;
        "9_monitoring")
            tar xzf "$latest_backup/monitoring_backup.tar.gz" -C / 2>/dev/null || true
            systemctl restart rsyslog aide rkhunter
            ;;
        *)
            tar xzf "$latest_backup/full_backup.tar.gz" -C / 2>/dev/null || true
            ;;
    esac
    
    log_message "Rollback completed to stage: $target_stage" "SUCCESS"
}

list_points() {
    echo "Available rollback points:"
    find "$BACKUP_DIR" -name "rollback_*" -type d -exec basename {} \; | sort
}

usage() {
    echo "Usage: $0 {create|rollback|list} [point_name]"
    echo "Commands:"
    echo "  create <point_name>  - Create a new rollback point"
    echo "  rollback <stage>     - Rollback to specified stage"
    echo "  list                 - List available rollback points"
    exit 1
}

main() {
    if [ $# -lt 1 ]; then
        usage
    fi
    
    ensure_dirs
    
    case "$1" in
        create)
            if [ -z "${2:-}" ]; then
                echo "Error: Point name required for create command"
                usage
            fi
            create_rollback_point "$2"
            ;;
        rollback)
            if [ -z "${2:-}" ]; then
                echo "Error: Stage required for rollback command"
                usage
            fi
            rollback "$2"
            ;;
        list)
            list_points
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"