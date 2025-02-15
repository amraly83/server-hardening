#!/bin/bash

set -euo pipefail

# Load configuration
source ./ubuntu.cfg

# Execution order with proper dependencies
declare -A COMPONENTS=(
    ["system_prep"]="createPartitions.sh"
    ["initial_hardening"]="ubuntu.sh"
    ["state_tracking"]="deployment_state.sh"
    ["cluster_setup"]="scripts/cluster_sync.sh"
    ["monitoring"]="monitor_security.sh"
    ["key_management"]="scripts/add_ssh_key.sh"
)

# Stage definitions with dependencies
declare -A STAGES=(
    ["1_prep"]="system_prep"
    ["2_hardening"]="initial_hardening"
    ["3_monitoring"]="state_tracking monitoring"
    ["4_cluster"]="cluster_setup key_management"
)

run_stage() {
    local stage_name="$1"
    local components="${STAGES[$stage_name]}"
    
    echo "=== Executing stage: $stage_name ==="
    
    for component in $components; do
        local script="${COMPONENTS[$component]}"
        echo "Running component: $component ($script)"
        
        if ! bash "$script"; then
            echo "Failed to execute $component"
            return 1
        fi
    done
}

# Verify stage completion
verify_stage() {
    local stage="$1"
    
    case "$stage" in
        "1_prep")
            # Verify system preparation
            if ! systemctl is-active --quiet rsyslog; then
                return 1
            fi
            ;;
        "2_hardening")
            # Verify core hardening
            if ! bash ./integration_tests.sh; then
                return 1
            fi
            ;;
        "3_monitoring")
            # Verify monitoring setup
            if ! systemctl is-active --quiet hardening-monitor; then
                return 1
            fi
            ;;
        "4_cluster")
            # Verify cluster health
            if ! bash ./scripts/cluster_sync.sh check_cluster; then
                return 1
            fi
            ;;
    esac
}

# Main deployment orchestration
main() {
    # Check if resuming from previous stage
    RESUME_STAGE=""
    if [ -f "/var/lib/hardening/last_stage" ]; then
        RESUME_STAGE=$(cat "/var/lib/hardening/last_stage")
        echo "Resuming from stage: $RESUME_STAGE"
    fi
    
    # Execute stages in order
    for stage in "${!STAGES[@]}"; do
        if [ -n "$RESUME_STAGE" ] && [ "$stage" \< "$RESUME_STAGE" ]; then
            echo "Skipping completed stage: $stage"
            continue
        fi
        
        echo "$stage" > "/var/lib/hardening/last_stage"
        
        if ! run_stage "$stage"; then
            echo "Stage $stage failed"
            exit 1
        fi
        
        if ! verify_stage "$stage"; then
            echo "Stage $stage verification failed"
            exit 1
        fi
        
        echo "Stage $stage completed successfully"
    done
    
    echo "Full deployment completed successfully"
}

main "$@"