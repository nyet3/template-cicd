#!/bin/bash
set -e

# Kubernetes Keycloak Setup Script
# Creates realm, users, roles, and clients for template-cicd

KEYCLOAK_URL="${KEYCLOAK_URL:-https://localhost:8443}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
REALM="${REALM:-testrealm}"

echo "🔐 Keycloak Initial Data Setup"
echo "=============================="
echo "Keycloak URL: $KEYCLOAK_URL"
echo "Realm: $REALM"
echo ""

# Function to get admin access token
get_access_token() {
  TOKEN_RESPONSE=$(curl -k -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASSWORD" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")
  
  ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
  
  if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Failed to get access token"
    exit 1
  fi
}

# Get initial token
echo "📝 Getting admin access token..."
get_access_token
echo "✅ Access token obtained"

# =============================================================================
# REALM SETUP
# =============================================================================
echo ""
echo "🏰 Setting up realm '$REALM'..."

EXISTING_REALM=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM" \
  -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null || echo "")

if echo "$EXISTING_REALM" | grep -q "\"realm\":\"$REALM\""; then
  echo "⚠️  Realm '$REALM' already exists, skipping creation"
else
  echo "📝 Creating realm '$REALM'..."
  
  REALM_JSON=$(cat <<EOF
{
  "realm": "$REALM",
  "enabled": true,
  "sslRequired": "none",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "accessTokenLifespan": 3600,
  "ssoSessionIdleTimeout": 36000,
  "ssoSessionMaxLifespan": 36000
}
EOF
)
  
  RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$REALM_JSON")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Realm '$REALM' created successfully"
  else
    echo "❌ Failed to create realm (HTTP $HTTP_CODE)"
    exit 1
  fi
fi

# =============================================================================
# ROLES SETUP
# =============================================================================
echo ""
echo "� Setting up roles..."

ROLES=("user" "admin" "manager" "viewer" "editor" "beginner")

for ROLE in "${ROLES[@]}"; do
  EXISTING_ROLE=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/roles/$ROLE" \
    -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null || echo "")
  
  if echo "$EXISTING_ROLE" | grep -q "\"name\":\"$ROLE\""; then
    echo "  ⚠️  Role '$ROLE' already exists"
  else
    echo "  📝 Creating role: $ROLE"
    
    ROLE_JSON=$(cat <<EOF
{
  "name": "$ROLE",
  "description": "$(echo $ROLE | sed 's/.*/\u&/') role"
}
EOF
)
    
    curl -k -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/roles" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$ROLE_JSON" > /dev/null
    
    echo "  ✅ Role '$ROLE' created"
  fi
done

# =============================================================================
# GROUPS SETUP
# =============================================================================
echo ""
echo "👥 Setting up groups..."

GROUPS=("Administrators" "Developers" "Managers" "Operations" "Viewers" "Beginners")

for GROUP in "${GROUPS[@]}"; do
  echo "  📝 Creating group: $GROUP"
  
  EXISTING_GROUP=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | grep "\"name\":\"$GROUP\"" || echo "")
  
  if [ -n "$EXISTING_GROUP" ]; then
    echo "  ⚠️  Group '$GROUP' already exists"
  else
    GROUP_JSON=$(cat <<EOF
{
  "name": "$GROUP"
}
EOF
)
    
    curl -k -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$GROUP_JSON" > /dev/null
    
    echo "  ✅ Group '$GROUP' created"
  fi
done

echo ""
echo "👑 Assigning roles to groups..."

# Function to assign roles to group
assign_roles_to_group() {
  local GROUP_NAME=$1
  shift
  local ROLES=("$@")
  
  # Get group ID
  GROUP_ID=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | grep -B2 "\"name\":\"$GROUP_NAME\"" | grep "\"id\"" | head -1 | cut -d'"' -f4)
  
  if [ -z "$GROUP_ID" ]; then
    echo "  ⚠️  Group '$GROUP_NAME' not found"
    return
  fi
  
  # Assign roles
  for ROLE in "${ROLES[@]}"; do
    # Get role details
    ROLE_DATA=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/roles/$ROLE" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
    
    # Assign role to group
    curl -k -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/groups/$GROUP_ID/role-mappings/realm" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "[$ROLE_DATA]" > /dev/null
  done
  
  echo "  ✅ Roles assigned to '$GROUP_NAME': ${ROLES[*]}"
}

assign_roles_to_group "Administrators" "admin" "manager"
assign_roles_to_group "Developers" "user" "editor"
assign_roles_to_group "Managers" "manager" "user"
assign_roles_to_group "Operations" "user"
assign_roles_to_group "Viewers" "viewer"
assign_roles_to_group "Beginners" "beginner"

# =============================================================================
# CLIENTS SETUP
# =============================================================================
echo ""
echo "🔑 Setting up clients..."

# Backend Client
BACKEND_CLIENT_ID="backend-client"
echo "  📝 Setting up backend client..."

EXISTING_BACKEND=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$BACKEND_CLIENT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$EXISTING_BACKEND" | grep -q "\"clientId\":\"$BACKEND_CLIENT_ID\""; then
  echo "  ⚠️  Backend client already exists"
else
  BACKEND_JSON=$(cat <<EOF
{
  "clientId": "$BACKEND_CLIENT_ID",
  "enabled": true,
  "publicClient": false,
  "protocol": "openid-connect",
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true,
  "authorizationServicesEnabled": false,
  "redirectUris": ["*"],
  "webOrigins": ["*"],
  "secret": "backend-secret-changeme"
}
EOF
)
  
  curl -k -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BACKEND_JSON" > /dev/null
  
  echo "  ✅ Backend client created"
fi

# Frontend Client
FRONTEND_CLIENT_ID="frontend-client"
echo "  📝 Setting up frontend client..."

EXISTING_FRONTEND=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$FRONTEND_CLIENT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$EXISTING_FRONTEND" | grep -q "\"clientId\":\"$FRONTEND_CLIENT_ID\""; then
  echo "  ⚠️  Frontend client already exists"
  
  # Update existing client
  CLIENT_UUID=$(echo $EXISTING_FRONTEND | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  
  FRONTEND_JSON=$(cat <<EOF
{
  "clientId": "$FRONTEND_CLIENT_ID",
  "enabled": true,
  "publicClient": true,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "implicitFlowEnabled": false,
  "redirectUris": [
    "https://localhost:5173/*",
    "https://localhost:3000/*",
    "https://app.example.com/*"
  ],
  "webOrigins": ["+"],
  "attributes": {
    "post.logout.redirect.uris": "+"
  }
}
EOF
)
  
  curl -k -s -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$FRONTEND_JSON" > /dev/null
  
  echo "  ✅ Frontend client updated"
else
  FRONTEND_JSON=$(cat <<EOF
{
  "clientId": "$FRONTEND_CLIENT_ID",
  "enabled": true,
  "publicClient": true,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "implicitFlowEnabled": false,
  "redirectUris": [
    "https://localhost:5173/*",
    "https://localhost:3000/*",
    "https://app.example.com/*"
  ],
  "webOrigins": ["+"],
  "attributes": {
    "post.logout.redirect.uris": "+"
  }
}
EOF
)
  
  curl -k -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$FRONTEND_JSON" > /dev/null
  
  echo "  ✅ Frontend client created"
fi

echo ""
echo "👥 Creating users..."

# =============================================================================
# CREATE USER FUNCTION
# =============================================================================
create_user() {
  local USERNAME="$1"
  local EMAIL="$2"
  local FIRSTNAME="$3"
  local LASTNAME="$4"
  local PASSWORD="$5"
  local GROUP="$6"
  
  echo "  📝 Creating user: $USERNAME"
  
  EXISTING_USER=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$USERNAME" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
  
  if echo "$EXISTING_USER" | grep -q "\"username\":\"$USERNAME\""; then
    echo "  ⚠️  User '$USERNAME' already exists"
    return
  fi
  
  USER_JSON=$(cat <<EOF
{
  "username": "$USERNAME",
  "email": "$EMAIL",
  "firstName": "$FIRSTNAME",
  "lastName": "$LASTNAME",
  "enabled": true,
  "emailVerified": true,
  "credentials": [{
    "type": "password",
    "value": "$PASSWORD",
    "temporary": false
  }]
}
EOF
)
  
  USER_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$USER_JSON")
  
  HTTP_CODE=$(echo "$USER_RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" -ne 201 ]; then
    echo "  ❌ Failed to create user '$USERNAME'"
    return
  fi
  
  # Get user ID
  sleep 1
  USER_ID=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$USERNAME" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  
  # Assign to group (roles inherited from group)
  if [ -n "$GROUP" ]; then
    GROUP_ID=$(curl -k -s -X GET "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
      -H "Authorization: Bearer $ACCESS_TOKEN" | grep -B2 "\"name\":\"$GROUP\"" | grep "\"id\"" | head -1 | cut -d'"' -f4)
    
    if [ -n "$GROUP_ID" ]; then
      curl -k -s -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID/groups/$GROUP_ID" \
        -H "Authorization: Bearer $ACCESS_TOKEN" > /dev/null
    fi
  fi
  
  echo "  ✅ User '$USERNAME' created [group: $GROUP]"
}

# Create users
create_user "admin" "admin@example.com" "Admin" "User" "admin123" "Administrators"
create_user "testuser" "test@example.com" "Test" "User" "testpass123" "Developers"
create_user "manager" "manager@example.com" "Manager" "User" "manager123" "Managers"
create_user "viewer" "viewer@example.com" "Viewer" "User" "viewer123" "Viewers"
create_user "beginner" "beginner@example.com" "Beginner" "User" "beginner123" "Beginners"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "🎉 Keycloak setup completed successfully!"
echo ""
echo "═══════════════════════════════════════════"
echo "📋 Configuration Summary"
echo "═══════════════════════════════════════════"
echo ""
echo "🏢 Realm: $REALM"
echo ""
echo "👤 Roles:"
echo "  - admin"
echo "  - manager"
echo "  - user"
echo "  - editor"
echo "  - viewer"
echo "  - beginner"
echo ""
echo "👥 Groups:"
echo "  - Administrators (roles: admin, manager)"
echo "  - Developers (roles: user, editor)"
echo "  - Managers (roles: manager, user)"
echo "  - Operations (roles: user)"
echo "  - Viewers (roles: viewer)"
echo "  - Beginners (roles: beginner)"
echo ""
echo "🔑 Clients:"
echo "  - backend-client (confidential)"
echo "  - frontend-client (public)"
echo ""
echo "👤 Users:"
echo "  ┌────────────┬──────────────────────┬─────────────┬───────────────┬──────────────────────┐"
echo "  │ Username   │ Email                │ Password    │ Group         │ Roles (inherited)    │"
echo "  ├────────────┼──────────────────────┼─────────────┼───────────────┼──────────────────────┤"
echo "  │ admin      │ admin@example.com    │ admin123    │ Administrators│ admin, manager       │"
echo "  │ testuser   │ test@example.com     │ testpass123 │ Developers    │ user, editor         │"
echo "  │ manager    │ manager@example.com  │ manager123  │ Managers      │ manager, user        │"
echo "  │ viewer     │ viewer@example.com   │ viewer123   │ Viewers       │ viewer               │"
echo "  │ beginner   │ beginner@example.com │ beginner123 │ Beginners     │ beginner (login only)│"
echo "  └────────────┴──────────────────────┴─────────────┴───────────────┴──────────────────────┘"
echo ""
echo "🌐 Access URLs:"
echo "  - Realm: $KEYCLOAK_URL/realms/$REALM"
echo "  - Admin Console: $KEYCLOAK_URL/admin/"
echo "  - Account Console: $KEYCLOAK_URL/realms/$REALM/account/"
echo ""
echo "✅ You can now use these credentials to login to the application!"
