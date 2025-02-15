#!/bin/bash

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Ubuntu Server Hardening Configuration Helper ===${NC}"
echo "This script will help you create your configuration file."
echo

# Check if config already exists
if [ -f "ubuntu.cfg" ]; then
    read -p "Configuration file already exists. Do you want to create a new one? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Copy example config
cp ubuntu.cfg.example ubuntu.cfg

# Interactive configuration
echo "Please provide the following information:"
echo

# Admin user
read -p "Enter admin username (letters and numbers only): " admin_user
while [[ ! $admin_user =~ ^[a-zA-Z0-9]+$ ]]; do
    echo "Username can only contain letters and numbers"
    read -p "Enter admin username: " admin_user
done

# Admin password
read -s -p "Enter admin password (min 12 characters): " admin_pass
echo
while [ ${#admin_pass} -lt 12 ]; do
    echo "Password must be at least 12 characters long"
    read -s -p "Enter admin password: " admin_pass
    echo
done

# Confirm password
read -s -p "Confirm admin password: " admin_pass_confirm
echo
while [ "$admin_pass" != "$admin_pass_confirm" ]; do
    echo "Passwords do not match"
    read -s -p "Enter admin password: " admin_pass
    echo
    read -s -p "Confirm admin password: " admin_pass_confirm
    echo
done

# SSH Port
read -p "Enter custom SSH port (1024-65535) [3333]: " ssh_port
ssh_port=${ssh_port:-3333}
while ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1024 ] || [ "$ssh_port" -gt 65535 ]; do
    echo "Port must be a number between 1024 and 65535"
    read -p "Enter custom SSH port: " ssh_port
done

# Admin email
read -p "Enter admin email for notifications: " admin_email
while ! echo "$admin_email" | grep -E -q '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; do
    echo "Please enter a valid email address"
    read -p "Enter admin email: " admin_email
done

# Update configuration file
sed -i "s/^ADMIN_USER=.*/ADMIN_USER='$admin_user'/" ubuntu.cfg
sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD='$admin_pass'/" ubuntu.cfg
sed -i "s/^SSH_PORT=.*/SSH_PORT='$ssh_port'/" ubuntu.cfg
sed -i "s/^ADMINEMAIL=.*/ADMINEMAIL='$admin_email'/" ubuntu.cfg

echo -e "\n${GREEN}Configuration created successfully!${NC}"
echo "Next steps:"
echo "1. Run: sudo bash check_config.sh"
echo "2. If all checks pass, run: sudo bash production_deploy.sh"
echo
echo "Make sure to save these details in a secure location:"
echo "- Admin username: $admin_user"
echo "- SSH port: $ssh_port"
echo "- Admin email: $admin_email"
echo
echo "Your server will be accessible via:"
echo "ssh -p $ssh_port $admin_user@YOUR_SERVER_IP"