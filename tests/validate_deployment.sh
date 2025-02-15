#!/bin/bash

set -euo pipefail

LOG_DIR="/var/log/hardening/tests"
TEST_REPORT="$LOG_DIR/test_report.xml"

# Test categories
declare -A TEST_SUITES=(
    ["ssh"]="tests/sshd.bats"
    ["firewall"]="tests/ufw.bats"
    ["audit"]="tests/auditd.bats"
    ["users"]="tests/users.bats"
    ["filesystem"]="tests/fstab.bats"
    ["kernel"]="tests/kernel.bats"
)

# Setup test environment
setup_test_env() {
    mkdir -p "$LOG_DIR"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > "$TEST_REPORT"
    echo "<testsuites>" >> "$TEST_REPORT"
}

# Run individual test suite
run_test_suite() {
    local suite="$1"
    local test_file="${TEST_SUITES[$suite]}"
    
    echo "Running test suite: $suite"
    echo "<testsuite name=\"$suite\">" >> "$TEST_REPORT"
    
    if ! bats --tap "$test_file" | tee -a "$LOG_DIR/${suite}.log" | while read -r line; do
        if [[ "$line" =~ ^ok[[:space:]]+(.*) ]]; then
            echo "<testcase name=\"${BASH_REMATCH[1]}\" classname=\"$suite\"/>" >> "$TEST_REPORT"
        elif [[ "$line" =~ ^not[[:space:]]+ok[[:space:]]+(.*) ]]; then
            echo "<testcase name=\"${BASH_REMATCH[1]}\" classname=\"$suite\">" >> "$TEST_REPORT"
            echo "  <failure>Test failed</failure>" >> "$TEST_REPORT"
            echo "</testcase>" >> "$TEST_REPORT"
        fi
    done; then
        return 1
    fi
    
    echo "</testsuite>" >> "$TEST_REPORT"
}

# Verify configuration consistency
verify_configs() {
    local config_files=(
        "/etc/ssh/sshd_config"
        "/etc/pam.d/common-auth"
        "/etc/audit/auditd.conf"
        "/etc/ufw/ufw.conf"
    )
    
    for file in "${config_files[@]}"; do
        echo "Verifying $file..."
        if ! diff -q "$file" "/var/backups/hardening/$(basename "$file")" &>/dev/null; then
            echo "WARNING: Configuration drift detected in $file"
            return 1
        fi
    done
}

# Run cluster-wide tests if in cluster mode
run_cluster_tests() {
    if [ -f "/etc/hardening/cluster_nodes" ]; then
        echo "Running cluster-wide tests..."
        while read -r node; do
            echo "Testing node: $node"
            if ! ssh "$node" 'bash -s' < "$0" --local-only; then
                echo "ERROR: Tests failed on node $node"
                return 1
            fi
        done < "/etc/hardening/cluster_nodes"
    fi
}

# Main test execution
main() {
    setup_test_env
    
    # Run all test suites
    local failed_suites=()
    for suite in "${!TEST_SUITES[@]}"; do
        if ! run_test_suite "$suite"; then
            failed_suites+=("$suite")
        fi
    done
    
    # Verify configuration consistency
    if ! verify_configs; then
        failed_suites+=("config_verification")
    fi
    
    # Run cluster tests unless --local-only flag is set
    if [[ "${1:-}" != "--local-only" ]]; then
        if ! run_cluster_tests; then
            failed_suites+=("cluster_tests")
        fi
    fi
    
    echo "</testsuites>" >> "$TEST_REPORT"
    
    # Report results
    if [ ${#failed_suites[@]} -gt 0 ]; then
        echo "The following test suites failed: ${failed_suites[*]}"
        exit 1
    fi
    
    echo "All tests passed successfully"
}

main "$@"