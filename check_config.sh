#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Pre-Installation Configuration Check ==="

# Check if config file exists
if [ ! -f "ubuntu.cfg" ]; then
    echo -e "${RED}Error: ubuntu.cfg not found!${NC}"
    echo "Please copy ubuntu.cfg.example to ubuntu.cfg and update the values."
    exit 1
fi

# Source configuration
source ./ubuntu.cfg

# Check required variables
check_required() {
    local var_name="$1"
    local var_value="$2"
    local example="$3"
    
    echo -n "Checking $var_name... "
    if [ -z "$var_value" ]; then
        echo -e "${RED}MISSING${NC}"
        echo "  Please set $var_name in ubuntu.cfg"
        echo "  Example: $var_name='$example'"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
    return 0
}

# Check SSH port validity
check_ssh_port() {
    echo -n "Validating SSH port... "
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
        echo -e "${RED}INVALID${NC}"
        echo "  SSH_PORT must be between 1024 and 65535"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
}

# Check email format
check_email_format() {
    echo -n "Validating email format... "
    if ! echo "$ADMINEMAIL" | grep -E -q '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
        echo -e "${RED}INVALID${NC}"
        echo "  Please provide a valid email address"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
}

# Check password strength
check_password_strength() {
    echo -n "Checking password strength... "
    local score=0
    
    # Length check
    if [ ${#ADMIN_PASSWORD} -ge 12 ]; then
        ((score++))
    fi
    
    # Uppercase check
    if echo "$ADMIN_PASSWORD" | grep -q [A-Z]; then
        ((score++))
    fi
    
    # Lowercase check
    if echo "$ADMIN_PASSWORD" | grep -q [a-z]; then
        ((score++))
    fi
    
    # Number check
    if echo "$ADMIN_PASSWORD" | grep -q [0-9]; then
        ((score++))
    fi
    
    # Special character check
    if echo "$ADMIN_PASSWORD" | grep -q '[!@#$%^&*()_+{}|:<>?]'; then
        ((score++))
    fi
    
    if [ $score -lt 3 ]; then
        echo -e "${RED}WEAK${NC}"
        echo "  Password should contain at least 12 characters with a mix of:"
        echo "  - Uppercase letters"
        echo "  - Lowercase letters"
        echo "  - Numbers"
        echo "  - Special characters"
        return 1
    elif [ $score -lt 5 ]; then
        echo -e "${YELLOW}MODERATE${NC}"
        echo "  Consider making your password stronger"
    else
        echo -e "${GREEN}STRONG${NC}"
    fi
}

# Check system requirements
check_system_requirements() {
    echo "Checking system requirements..."
    
    # Check Ubuntu version
    echo -n "Ubuntu version... "
    if ! lsb_release -d | grep -q "Ubuntu 22.04"; then
        echo -e "${YELLOW}WARNING${NC}"
        echo "  This script is tested on Ubuntu 22.04 LTS"
        echo "  Your version: $(lsb_release -d | cut -f2)"
    else
        echo -e "${GREEN}OK${NC}"
    fi
    
    # Check available disk space
    echo -n "Available disk space... "
    local available_space=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    if [ "${available_space%.*}" -lt 5 ]; then
        echo -e "${RED}INSUFFICIENT${NC}"
        echo "  At least 5GB free space required"
        echo "  Available: ${available_space}GB"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
    
    # Check memory
    echo -n "System memory... "
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 1024 ]; then
        echo -e "${RED}INSUFFICIENT${NC}"
        echo "  At least 1GB RAM required"
        echo "  Available: ${total_mem}MB"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"
}

# Main execution
echo "Starting configuration verification..."
echo

errors=0

check_required "ADMIN_USER" "$ADMIN_USER" "admin" || ((errors++))
check_required "ADMIN_PASSWORD" "$ADMIN_PASSWORD" "StrongP@ssw0rd" || ((errors++))
check_required "SSH_PORT" "$SSH_PORT" "3333" || ((errors++))
check_required "ADMINEMAIL" "$ADMINEMAIL" "admin@example.com" || ((errors++))

echo
check_ssh_port || ((errors++))
check_email_format || ((errors++))
check_password_strength || ((errors++))
echo
check_system_requirements || ((errors++))

echo
if [ $errors -eq 0 ]; then
    echo -e "${GREEN}All checks passed! You can proceed with the installation.${NC}"
    echo "Run: sudo bash production_deploy.sh"
else
    echo -e "${RED}Found $errors configuration issues that need to be fixed.${NC}"
    echo "Please correct the issues and run this check again."
    exit 1
fi