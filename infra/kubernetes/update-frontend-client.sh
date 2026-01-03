#!/bin/bash
set -e

KEYCLOAK_URL="https://localhost:8443"
REALM="testrealm"

echo "🔧 Updating frontend client with HTTP and HTTPS redirect URIs..."

TOKEN=$(curl -k -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Failed to get access token"
  exit 1
fi

CLIENT_UUID=$(curl -k -s "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.[] | select(.clientId=="frontend-client") | .id')

echo "Client UUID: $CLIENT_UUID"

cat > /tmp/frontend-client.json <<'EOF'
{
  "clientId": "frontend-client",
  "enabled": true,
  "publicClient": true,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "implicitFlowEnabled": false,
  "redirectUris": [
    "https://localhost:5173/*",
    "http://localhost:5173/*",
    "https://localhost:3000/*",
    "http://localhost:3000/*",
    "https://app.example.com/*"
  ],
  "webOrigins": ["*"],
  "rootUrl": "",
  "baseUrl": "",
  "attributes": {
    "post.logout.redirect.uris": "https://localhost:5173/* http://localhost:5173/*"
  }
}
EOF

curl -k -s -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/frontend-client.json

echo ""
echo "✅ Frontend client updated with both HTTP and HTTPS URIs"
echo ""
echo "📋 Current configuration:"
curl -k -s "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID" \
  -H "Authorization: Bearer $TOKEN" | jq '{clientId, redirectUris, webOrigins, attributes}'
