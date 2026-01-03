#!/bin/bash
set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
REALM="${REALM:-master}"
CLIENT_ID="${CLIENT_ID:-frontend-client}"
REDIRECT_URI="${REDIRECT_URI:-http://localhost:5173/*}"

echo "🔐 Keycloak Client Setup Script"
echo "================================"
echo "Keycloak URL: $KEYCLOAK_URL"
echo "Realm: $REALM"
echo "Client ID: $CLIENT_ID"
echo ""

# Get admin access token
echo "📝 Getting admin access token..."
TOKEN_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" \
  -d "client_id=admin-cli")

ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to get access token"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "✅ Access token obtained"

# Check if client already exists
echo ""
echo "🔍 Checking if client '$CLIENT_ID' exists..."
EXISTING_CLIENT=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

if echo "$EXISTING_CLIENT" | grep -q "\"clientId\":\"$CLIENT_ID\""; then
  echo "⚠️  Client '$CLIENT_ID' already exists"
  CLIENT_UUID=$(echo $EXISTING_CLIENT | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "Client UUID: $CLIENT_UUID"
  
  echo ""
  echo "🔄 Updating existing client..."
else
  echo "📝 Client does not exist, creating new client..."
  CLIENT_UUID=""
fi

# Create or update client
CLIENT_JSON=$(cat <<EOF
{
  "clientId": "$CLIENT_ID",
  "enabled": true,
  "publicClient": true,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "implicitFlowEnabled": false,
  "serviceAccountsEnabled": false,
  "redirectUris": [
    "$REDIRECT_URI",
    "http://localhost:5173/callback"
  ],
  "webOrigins": [
    "http://localhost:5173"
  ],
  "attributes": {
    "post.logout.redirect.uris": "http://localhost:5173/*"
  }
}
EOF
)

if [ -z "$CLIENT_UUID" ]; then
  # Create new client
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CLIENT_JSON")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Client '$CLIENT_ID' created successfully"
  else
    echo "❌ Failed to create client (HTTP $HTTP_CODE)"
    echo "$RESPONSE" | head -n-1
    exit 1
  fi
else
  # Update existing client
  RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CLIENT_JSON")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" -eq 204 ]; then
    echo "✅ Client '$CLIENT_ID' updated successfully"
  else
    echo "❌ Failed to update client (HTTP $HTTP_CODE)"
    echo "$RESPONSE" | head -n-1
    exit 1
  fi
fi

echo ""
echo "🎉 Keycloak client setup completed!"
echo ""
echo "Client configuration:"
echo "  - Client ID: $CLIENT_ID"
echo "  - Type: Public (no client secret required)"
echo "  - Redirect URIs: $REDIRECT_URI"
echo "  - Web Origins: http://localhost:5173"
echo ""
echo "You can now rebuild the frontend with:"
echo "  CLIENT_ID=$CLIENT_ID"
