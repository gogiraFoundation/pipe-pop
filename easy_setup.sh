#!/bin/bash

# Pipe PoP Node Easy Setup Script
# Version: 1.2.0
#
# This script provides a one-command setup for the Pipe PoP node
#
# NOTE: This is a more user-friendly version of setup.sh that provides
# a guided installation process with interactive prompts. If you prefer
# a non-interactive setup, you can use setup.sh instead.
#
# Contributors:
# - Preterag Team (original implementation)
# - Community contributors welcome! See README.md for contribution guidelines

set -e
set -o pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define log file with timestamp
LOG_FILE="/var/log/pipe-pop-setup_$(date +%Y%m%d_%H%M%S).log"
sudo mkdir -p /var/log/
sudo touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1



# Logging functions
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} $1" >&2; }

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root. Use sudo."
    exit 1
fi

# Cleanup function on exit
cleanup() {
    rm -rf "$TEMP_DIR"
    log "Cleaned up temporary files."
}
trap cleanup EXIT

# Display welcome message
clear
log "Pipe PoP Easy Setup Tool v1.2.0"
log "Setting up Pipe PoP node for the Pipe Network decentralized CDN."

read -p "Press Enter to continue or Ctrl+C to cancel..."

# Function to install required packages efficiently
install_dependencies() {
    log "Installing required packages..."
    local packages=(curl net-tools jq git)
    local to_install=()
    for pkg in "${packages[@]}"; do
        dpkg -s "$pkg" &>/dev/null || to_install+=("$pkg")
    done
    if [ "${#to_install[@]}" -gt 0 ]; then
        apt-get update && apt-get install -y "${to_install[@]}" || { error "Failed to install packages"; exit 1; }
    else
        log "All required packages are already installed."
    fi
}

# Function to setup Pipe PoP Node
setup_pipe_pop() {
    INSTALL_DIR="/opt/pipe-pop"
    log "Setting up Pipe PoP Node..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    if [ -d ".git" ]; then
        log "Updating existing repository..."
        git pull || { error "Failed to update Pipe PoP repository."; exit 1; }
    else
        log "Cloning Pipe PoP repository..."
        git clone https://github.com/preterag/pipecdn.git "$INSTALL_DIR" || { error "Failed to clone repository."; exit 1; }
    fi
}

# Function to setup Solana wallet
setup_solana_wallet() {
    log "Installing Solana CLI..."
    sh -c "$(curl -sSfL https://release.solana.com/stable/install)" || { error "Solana CLI installation failed."; exit 1; }
    source ~/.bashrc
    read -p "Create a new Solana wallet? (y/n): " create_wallet
    if [[ "$create_wallet" =~ ^[yY]$ ]]; then
        solana-keygen new --no-passphrase
        SOLANA_WALLET=$(solana address)
        log "Wallet created: $SOLANA_WALLET"
    else
        read -p "Enter existing Solana wallet address: " SOLANA_WALLET
        log "Using provided wallet address: $SOLANA_WALLET"
    fi
}

# Function to setup systemd service
setup_systemd_service() {
    log "Setting up systemd service..."
    cat > /etc/systemd/system/pipe-pop.service << EOF
[Unit]
Description=Pipe PoP Node
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=/opt/pipe-pop
ExecStart=/opt/pipe-pop/bin/pipe-pop --cache-dir /opt/pipe-pop/cache --pubKey $SOLANA_WALLET --enable-80-443
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
ProtectSystem=full
NoNewPrivileges=true
MemoryLimit=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now pipe-pop.service
    log "Service started. Checking status..."
    systemctl status pipe-pop --no-pager
}

# Function to install a global command
install_global_command() {
    log "Installing global 'pop' command..."
    cat > /usr/local/bin/pop << 'EOF'
#!/bin/bash
INSTALL_DIR="/opt/pipe-pop"
"$INSTALL_DIR/bin/pipe-pop" "$@"
EOF
    chmod +x /usr/local/bin/pop
    log "'pop' command installed successfully."
}

# Function to setup update mechanism
install_update_command() {
    log "Installing update command 'pop-update'..."
    cat > /usr/local/bin/pop-update << 'EOF'
#!/bin/bash
cd /usr/local/bin && sudo curl -O https://raw.githubusercontent.com/preterag/pipecdn/main/setup.sh
chmod +x /usr/local/bin/pipe-pop-setup.sh
EOF
    chmod +x /usr/local/bin/pop-update
    log "'pop-update' command installed successfully."
}

# Main execution flow
install_dependencies
setup_pipe_pop
setup_solana_wallet
setup_systemd_service
install_global_command
install_update_command

log "Pipe PoP node setup completed successfully. Use 'pop' to manage your node."