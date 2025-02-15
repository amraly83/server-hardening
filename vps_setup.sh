#!/bin/bash

# Clone the hardening repository
git clone https://github.com/amraly83/server-hardening.git
cd server-hardening

# Update configuration
nano ubuntu.cfg

# Run the hardening script
sudo bash ubuntu.sh