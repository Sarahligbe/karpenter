#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Go on Linux
install_go_linux() {
    echo "Installing Go on Linux..."
    GO_VERSION="1.21.5"  # Update this to the latest version as needed
    wget https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
    source ~/.bashrc
}

# Main script
if ! command_exists go; then
    echo "Go is not installed. Installing now..."
    install_go_linux
    
    # Verify installation
    if ! command_exists go; then
        echo "Failed to install Go. Please install it manually."
        exit 1
    fi
fi

echo "Go is installed. Proceeding with key generation..."

# Set variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
KEYS_DIR="${SCRIPT_DIR}/keys"
KEYS_GENERATOR_DIR="${SCRIPT_DIR}/keys-generator"
PRIV_KEY="${KEYS_DIR}/oidc-issuer.key"
PUB_KEY="${KEYS_DIR}/oidc-issuer.key.pub"
PKCS_KEY="${KEYS_DIR}/oidc-issuer.pub"
KEYS_FILE="${KEYS_DIR}/keys.json"
DISCOVERY_FILE="${SCRIPT_DIR}/aws/discovery.json"
GO_FILE="https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/refs/heads/master/hack/self-hosted/main.go"

#install jq
sudo apt update
sudo apt install jq

# Ensure the keys directory exists
mkdir -p "$KEYS_DIR"

# Generate the RSA key pair
echo "Generating RSA key pair..."
ssh-keygen -t rsa -b 2048 -f "$PRIV_KEY" -m pem -N ""

# Convert the SSH pubkey to PKCS8
echo "Converting public key to PKCS8 format..."
ssh-keygen -e -m PKCS8 -f "$PUB_KEY" > "$PKCS_KEY"

# Run the Go script to generate JWKS
echo "Generating JWKS key set..."
curl -o "$KEYS_DIR/main.go" "$GO_FILE"
sed -i 's@\(/v[0-9]*\)@@g' "$KEYS_DIR/main.go"

cd $KEYS_DIR
go mod init awsPodIdentity
go mod tidy
if go run main.go -key "$PKCS_KEY" | jq > "$KEYS_FILE"; then
    echo "JWKS key set generated successfully at $KEYS_FILE"
else
    echo "Error generating JWKS key set"
    exit 1
fi

echo "All keys have been generated successfully."