#!/bin/bash

set -euo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ubuntu.cfg"

# Setup logging
LOGFILE="integration-tests-$(date +%Y%m%d_%H%M%S).log"

# Ensure required variables are set
: "${SSH_PORT:=22}"

# Integration test suite
run_integration_tests() {
    local test_status=0
    
    # Test SSH Configuration
    test_ssh_config() {
        local tests=(
            "Protocol 2"
            "PermitRootLogin no"
            "PasswordAuthentication no"
            "X11Forwarding no"
            "MaxAuthTries 3"
            "AllowGroups sudo"
        )
        
        for test in "${tests[@]}"; do
            if ! sshd -T | grep -q "^${test}"; then
                echo "FAIL: SSH config test - ${test}"
                test_status=1
            fi
        done
    }
    
    # Test Firewall Configuration
    test_firewall_config() {
        # Verify SSH port is the only allowed incoming port
        if ! ufw status | grep -q "^$SSH_PORT/tcp.*ALLOW.*"; then
            echo "FAIL: SSH port not properly configured in firewall"
            test_status=1
        fi
        
        # Verify default deny policy
        if ! ufw status | grep -q "Default:.*deny.*incoming"; then
            echo "FAIL: Firewall default deny policy not set"
            test_status=1
        fi
    }
    
    # Test PAM Configuration
    test_pam_config() {
        local required_modules=(
            "pam_pwquality.so"
            "pam_google_authenticator.so"
            "pam_faillock.so"
        )
        
        for module in "${required_modules[@]}"; do
            if ! grep -q "$module" /etc/pam.d/*; then
                echo "FAIL: PAM module $module not configured"
                test_status=1
            fi
        done
    }
    
    # Test System Auditing
    test_audit_config() {
        if ! auditctl -l | grep -q "dir=/home/"; then
            echo "FAIL: Home directory auditing not configured"
            test_status=1
        fi
        
        if ! auditctl -l | grep -q "key=privileged"; then
            echo "FAIL: Privileged command auditing not configured"
            test_status=1
        fi
    }
    
    # Run all tests
    echo "Starting integration tests..."
    test_ssh_config
    test_firewall_config
    test_pam_config
    test_audit_config
    
    # Report results
    if [ $test_status -eq 0 ]; then
        echo "All integration tests passed!"
    else
        echo "Some integration tests failed. Check $LOGFILE for details."
        return 1
    fi
}

# Run the test suite
run_integration_tests 2>&1 | tee -a "$LOGFILE"