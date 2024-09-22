#!/bin/bash

curl -s https://raw.githubusercontent.com/zunxbt/logo/main/logo.sh | bash

sleep 3

ARCH=$(uname -m)

show() {
    echo -e "\033[1;35m$1\033[0m"
}

if ! command -v jq &> /dev/null; then
    show "jq not found, installing..."
    sudo apt-get update
    sudo apt-get install -y jq > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        show "Failed to install jq. Please check your package manager."
        exit 1
    fi
fi

check_latest_version() {
    for i in {1..3}; do
        LATEST_VERSION=$(curl -s https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r '.tag_name')
        if [ -n "$LATEST_VERSION" ]; then
            show "Latest version available: $LATEST_VERSION"
            return 0
        fi
        show "Attempt $i: Failed to fetch the latest version. Retrying..."
        sleep 2
    done

    show "Failed to fetch the latest version after 3 attempts. Please check your internet connection or GitHub API limits."
    exit 1
}

check_latest_version

download_required=true

if [ "$ARCH" == "x86_64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_amd64" ]; then
        show "Latest version for x86_64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
elif [ "$ARCH" == "arm64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_arm64" ]; then
        show "Latest version for arm64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
fi

if [ "$download_required" = true ]; then
    if [ "$ARCH" == "x86_64" ]; then
        show "Downloading for x86_64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
    elif [ "$ARCH" == "arm64" ]; then
        show "Downloading for arm64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
    else
        show "Unsupported architecture: $ARCH"
        exit 1
    fi
else
    show "Skipping download as the latest version is already present."
fi

echo
show "Select only one option:"
show "1. Use new wallet for PoP mining"
show "2. Use existing wallet for PoP mining"
read -p "Enter your choice (1/2): " choice
echo

if [ "$choice" == "1" ]; then
    show "Generating a new wallet..."
    ./keygen -secp256k1 -json -net="testnet" > ~/popm-address.json
    if [ $? -ne 0 ]; then
        show "Failed to generate wallet."
        exit 1
    fi
    cat ~/popm-address.json
    echo
    read -p "Have you saved the above details? (y/N): " saved
    echo
    if [[ "$saved" =~ ^[Yy]$ ]]; then
        pubkey_hash=$(jq -r '.pubkey_hash' ~/popm-address.json)
        show "Join: https://discord.gg/hemixyz"
        show "Request faucet from faucet channel to this address: $pubkey_hash"
        echo
        read -p "Have you requested faucet? (y/N): " faucet_requested
        if [[ "$faucet_requested" =~ ^[Yy]$ ]]; then
            priv_key=$(jq -r '.private_key' ~/popm-address.json)
            read -p "Enter static fee (numerical only, recommended: 100-200): " static_fee
            echo
        fi
    fi

elif [ "$choice" == "2" ]; then
    declare -a priv_keys  # Declare an array to hold private keys
    while true; do
        read -p "Enter your Private key (or type 'done' to finish): " priv_key
        if [[ "$priv_key" == "done" ]]; then
            break  # Exit the loop if the user is done
        fi
        priv_keys+=("$priv_key")  # Add the private key to the array
    done

    # Show the collected private keys
    echo "Collected Private Keys:"
    for key in "${priv_keys[@]}"; do
        echo "$key"
    done

    read -p "Enter static fee (numerical only, recommended: 100-200): " static_fee
    echo
fi

# Generate unique service file for the user based on username
SERVICE_NAME="hemi_${USER}.service"
WORKING_DIR=$(pwd)

if systemctl is-active --quiet "$SERVICE_NAME"; then
    show "$SERVICE_NAME is currently running. Stopping and disabling it..."
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl disable "$SERVICE_NAME"
else
    show "$SERVICE_NAME is not running."
fi

# Write unique systemd service file for the user
cat << EOF | sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null
[Unit]
Description=Hemi Network popmd Service for $USER
After=network.target

[Service]
WorkingDirectory=$WORKING_DIR
ExecStart=$WORKING_DIR/popmd
Environment="POPM_BTC_PRIVKEY=$(printf '%s,' "${priv_keys[@]}" | sed 's/,$//')"
Environment="POPM_STATIC_FEE=$static_fee"
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the user-specific service
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
echo
show "PoP mining is successfully started for user $USER"
