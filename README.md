# Ubuntu Server Hardening Script

This repository contains scripts for hardening Ubuntu 22.04 servers with strong security configurations.

## Initial Setup

1. Clone this repository on your Ubuntu 22.04 VPS:
```bash
git clone https://github.com/amraly83/server-hardening.git
cd server-hardening
```

2. Edit configuration (using nano):
```bash
nano ubuntu.cfg
```
Key settings to update:
- ADMIN_USER: Your admin username
- ADMIN_PASSWORD: Your secure admin password
- ADMINEMAIL: Your email for notifications
- SSH_PORT: Custom SSH port (default: 3333)

3. Run the hardening script as root:
```bash
sudo bash ubuntu.sh
```

## Security Features
- Creates secure admin user with sudo privileges
- Configures SSH with public key + 2FA authentication
- Implements strong password policies
- Enables UFW firewall with rate limiting
- Sets up audit logging and monitoring
- Configures kernel security parameters
- Enables AppArmor security profiles
- Sets up AIDE file integrity monitoring

## Post-Installation
1. After script completion, you'll need to:
   - Set up Google Authenticator for 2FA
   - Add your SSH public key to ~/.ssh/authorized_keys
   - Test login with new credentials before logging out

## Important Notes
- Root login will be disabled
- Password authentication will be disabled
- SSH port will be changed to 3333 (configurable)
- System will require reboot after hardening

## Requirements
- Ubuntu 22.04 64-bit
- Clean server installation
- Root access for initial setup