#!/bin/sh
set -e

CERT_DIR="/etc/nginx/certs"
CERT_FILE="$CERT_DIR/frontend.crt"
KEY_FILE="$CERT_DIR/frontend.key"

# Create cert directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Check if certificates already exist
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "SSL certificates already exist, skipping generation"
    exit 0
fi

echo "Generating self-signed SSL certificate for frontend..."

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Development/OU=Frontend/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:frontend,IP:127.0.0.1"

chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

# Create symlinks for K8s compatibility (tls.crt/tls.key)
ln -sf frontend.crt "$CERT_DIR/tls.crt"
ln -sf frontend.key "$CERT_DIR/tls.key"

echo "SSL certificate generated successfully"
