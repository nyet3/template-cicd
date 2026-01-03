#!/bin/bash
set -e

# Generate self-signed certificates for Kubernetes

CERT_DIR="${CERT_DIR:-./k8s-certs}"
DOMAIN="${DOMAIN:-localhost}"
DAYS="${DAYS:-365}"

echo "🔐 Generating Self-Signed Certificates for Kubernetes"
echo "======================================================"
echo "Domain: $DOMAIN"
echo "Validity: $DAYS days"
echo "Output directory: $CERT_DIR"
echo ""

mkdir -p "$CERT_DIR"

# Generate Frontend Certificate
echo "📝 Generating frontend certificate..."
openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
  -keyout "$CERT_DIR/frontend.key" \
  -out "$CERT_DIR/frontend.crt" \
  -subj "/CN=$DOMAIN/O=Template-CICD/C=JP" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,DNS:*.local,IP:127.0.0.1" \
  2>/dev/null

echo "✅ Frontend certificate generated"

# Generate Keycloak Certificate
echo "📝 Generating keycloak certificate..."
openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
  -keyout "$CERT_DIR/keycloak.key" \
  -out "$CERT_DIR/keycloak.crt" \
  -subj "/CN=$DOMAIN/O=Template-CICD/C=JP" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,DNS:keycloak,DNS:*.local,IP:127.0.0.1" \
  2>/dev/null

# Create Keycloak keystore (PKCS12)
echo "📝 Creating keycloak keystore..."
openssl pkcs12 -export \
  -in "$CERT_DIR/keycloak.crt" \
  -inkey "$CERT_DIR/keycloak.key" \
  -out "$CERT_DIR/keycloak.p12" \
  -name keycloak \
  -password pass:changeit \
  2>/dev/null

echo "✅ Keycloak certificate and keystore generated"

echo ""
echo "📦 Certificate files created:"
echo "  - $CERT_DIR/frontend.key"
echo "  - $CERT_DIR/frontend.crt"
echo "  - $CERT_DIR/keycloak.key"
echo "  - $CERT_DIR/keycloak.crt"
echo "  - $CERT_DIR/keycloak.p12"
echo ""
echo "🎉 Certificate generation completed!"
