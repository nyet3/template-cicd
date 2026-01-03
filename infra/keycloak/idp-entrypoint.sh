#!/usr/bin/env bash
set -euo pipefail

REALM=${KC_REALM:-testrealm}
CMD=("/opt/keycloak/bin/kc.sh" "$@")

# Generate a self-signed keystore for HTTPS if not present
KEYSTORE="/opt/keycloak/conf/server.keystore"
KEYPASS="${KEYCLOAK_KEYSTORE_PASSWORD:-changeit}"
if [[ ! -f "$KEYSTORE" ]]; then
  keytool -genkeypair \
    -storepass "$KEYPASS" \
    -keypass "$KEYPASS" \
    -keystore "$KEYSTORE" \
    -alias keycloak \
    -dname "CN=keycloak" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 3650
fi

echo "==> Starting Keycloak..."
"${CMD[@]}" &
KEYCLOAK_PID=$!

# wait for Keycloak to accept connections without requiring curl
echo "==> Waiting for Keycloak to be ready..."
until (echo > /dev/tcp/localhost/8080) >/dev/null 2>&1; do
  sleep 2
done

echo "==> Keycloak is ready, running setup scripts..."

# Run realm setup script
if [[ -f /opt/keycloak/bin/setup-realm.sh ]]; then
  echo "==> Running realm setup script..."
  bash /opt/keycloak/bin/setup-realm.sh
else
  echo "==> No realm setup script found, skipping..."
fi

echo "==> Keycloak is ready, running setup scripts..."

# Run realm setup script
if [[ -f /opt/keycloak/bin/setup-realm.sh ]]; then
  echo "==> Running realm setup script..."
  bash /opt/keycloak/bin/setup-realm.sh
else
  echo "==> No realm setup script found, skipping..."
fi

# Configure external IdP if environment variables are provided
if [[ -n "${ENTRA_TENANT_ID:-}" && -n "${ENTRA_CLIENT_ID:-}" && -n "${ENTRA_CLIENT_SECRET:-}" ]]; then
  echo "==> Configuring Entra ID (Azure AD) Identity Provider..."
  
  /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user "${KEYCLOAK_ADMIN}" \
    --password "${KEYCLOAK_ADMIN_PASSWORD}"
  
  cat > /tmp/entra-id.json <<EOF
{
  "alias": "${ENTRA_ALIAS:-entra-id}",
  "displayName": "${ENTRA_DISPLAY_NAME:-Entra ID}",
  "providerId": "oidc",
  "enabled": true,
  "trustEmail": true,
  "storeToken": true,
  "authenticateByDefault": false,
  "config": {
    "clientId": "${ENTRA_CLIENT_ID}",
    "clientSecret": "${ENTRA_CLIENT_SECRET}",
    "authorizationUrl": "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/authorize",
    "tokenUrl": "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token",
    "logoutUrl": "https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/logout",
    "defaultScope": "${ENTRA_SCOPES:-openid profile email}",
    "backchannelSupported": "true",
    "prompt": "login"
  }
}
EOF
  /opt/keycloak/bin/kcadm.sh create identity-provider/instances -r "${REALM}" -f /tmp/entra-id.json 2>/dev/null || \
  /opt/keycloak/bin/kcadm.sh update identity-provider/instances/"${ENTRA_ALIAS:-entra-id}" -r "${REALM}" -f /tmp/entra-id.json
  
  echo "==> Entra ID configuration complete"
fi

echo "==> Setup complete, Keycloak is ready for use"
wait "${KEYCLOAK_PID}"
