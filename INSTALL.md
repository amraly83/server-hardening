# Ubuntu Server Hardening - Installation Guide

## Prerequisites
- A fresh Ubuntu 22.04 LTS server installation
- Root or sudo access to your server
- Basic knowledge of how to connect to your server using SSH

## Step-by-Step Installation Guide

### 1. Initial Server Access
1. Connect to your server using SSH:
   ```
   ssh username@your_server_ip
   ```

### 2. Install Required Packages
1. Update your system:
   ```
   sudo apt update && sudo apt upgrade -y
   ```
2. Install required packages:
   ```
   sudo apt install git curl -y
   ```

### 3. Download the Hardening Scripts
1. Clone the repository:
   ```
   git clone https://github.com/amraly83/server-hardening.git
   cd server-hardening
   ```

### 4. Configure Your Settings
1. Make a copy of the example configuration:
   ```
   cp ubuntu.cfg.example ubuntu.cfg
   ```

2. Edit the configuration file:
   ```
   nano ubuntu.cfg
   ```

3. Set the following required values:
   - ADMIN_USER: Your new admin username
   - ADMIN_PASSWORD: A strong password for the admin user
   - SSH_PORT: Choose a custom SSH port (between 1024-65535)
   - ADMINEMAIL: Your email for security notifications

   Save the file by pressing CTRL+X, then Y, then Enter.

### 5. Run the Installation
1. Start the hardening process:
   ```
   sudo bash production_deploy.sh
   ```

2. The script will:
   - Create backups of your current configuration
   - Set up secure SSH configuration
   - Configure firewall rules
   - Enable system auditing
   - Set up intrusion detection
   - Configure automatic security updates

3. When prompted, confirm any questions with 'y'

### 6. Post-Installation Steps
1. The system will notify you when the installation is complete
2. Save the new SSH port number shown in the completion message
3. **IMPORTANT**: Keep your terminal session open and open a new terminal to verify access:
   ```
   ssh -p YOUR_NEW_PORT admin@your_server_ip
   ```

### 7. Set Up Two-Factor Authentication
1. After logging in as your admin user, run:
   ```
   google-authenticator
   ```
2. Follow the prompts and save your backup codes securely
3. Scan the QR code with Google Authenticator app on your phone

### 8. Verify Installation
1. Check system status:
   ```
   sudo systemctl status hardening-monitor
   ```
2. View security logs:
   ```
   sudo tail -f /var/log/hardening/system.log
   ```

### 9. Emergency Recovery
If you lose access to your server:
1. Log into your server's console through your hosting provider's control panel
2. Run the recovery script:
   ```
   cd server-hardening
   sudo bash recovery.sh
   ```

## Important Notes
- **DO NOT** close your initial SSH session until you've verified you can log in through a new session
- Save your 2FA backup codes in a secure location
- The default SSH port will be changed to your custom port
- Root login will be disabled
- Password authentication will be disabled (use SSH keys)
- System will automatically install security updates

## Support
If you need assistance:
1. Check the logs in `/var/log/hardening/`
2. File an issue on our GitHub repository
3. Contact your system administrator

## Security Reports
- Daily security reports will be sent to your specified email
- Check `/var/log/hardening/security-report.log` for latest security status

## Maintenance
The system will:
- Automatically update security patches
- Perform daily security scans
- Monitor for intrusion attempts
- Back up security configurations
- Send alerts for suspicious activities

## Troubleshooting
If you experience issues:
1. Check the installation logs:
   ```
   sudo cat /var/log/hardening/deployment-*.log
   ```
2. Run the validation tests:
   ```
   sudo bash tests/validate_deployment.sh
   ```
3. View system status:
   ```
   sudo bash scripts/health_monitor.sh status
   ```

Remember to keep your SSH private keys, 2FA backup codes, and admin credentials in a secure location!