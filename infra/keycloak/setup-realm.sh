#!/usr/bin/env bash
set -euo pipefail

# Keycloak Realm Setup Script
# This script configures Keycloak with realm, users, roles, and clients

REALM="${KC_REALM:-testrealm}"
KEYCLOAK_URL="http://localhost:8080"

echo "==> Waiting for Keycloak to be ready..."
until (echo > /dev/tcp/localhost/8080) >/dev/null 2>&1; do
  sleep 2
done

echo "==> Authenticating with Keycloak Admin API..."
/opt/keycloak/bin/kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${KEYCLOAK_ADMIN}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}"

echo "==> Checking if realm '${REALM}' exists..."
if /opt/keycloak/bin/kcadm.sh get realms/${REALM} &>/dev/null; then
  echo "    Realm '${REALM}' already exists, skipping realm creation"
else
  echo "==> Creating realm '${REALM}'..."
  /opt/keycloak/bin/kcadm.sh create realms \
    -s realm="${REALM}" \
    -s enabled=true \
    -s sslRequired=none \
    -s registrationAllowed=false \
    -s loginWithEmailAllowed=true \
    -s duplicateEmailsAllowed=false \
    -s resetPasswordAllowed=true \
    -s editUsernameAllowed=false \
    -s accessTokenLifespan=3600 \
    -s ssoSessionIdleTimeout=36000 \
    -s ssoSessionMaxLifespan=36000
fi

echo "==> Creating realm roles..."
for role in user admin manager viewer editor beginner; do
  if /opt/keycloak/bin/kcadm.sh get roles/${role} -r "${REALM}" &>/dev/null; then
    echo "    Role '${role}' already exists, skipping"
  else
    echo "    Creating role: ${role}"
    /opt/keycloak/bin/kcadm.sh create roles \
      -r "${REALM}" \
      -s name="${role}" \
      -s 'description='"${role^}"' role'
  fi
done

echo "==> Creating groups with roles..."
# Administrators group with admin and manager roles
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Administrators\""; then
  echo "    Group 'Administrators' already exists, skipping"
else
  echo "    Creating group: Administrators"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Administrators" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename admin --rolename manager
fi

# Developers group with user and editor roles
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Developers\""; then
  echo "    Group 'Developers' already exists, skipping"
else
  echo "    Creating group: Developers"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Developers" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename user --rolename editor
fi

# Managers group with manager and user roles
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Managers\""; then
  echo "    Group 'Managers' already exists, skipping"
else
  echo "    Creating group: Managers"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Managers" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename manager --rolename user
fi

# Operations group with user role
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Operations\""; then
  echo "    Group 'Operations' already exists, skipping"
else
  echo "    Creating group: Operations"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Operations" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename user
fi

# Viewers group with viewer role
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Viewers\""; then
  echo "    Group 'Viewers' already exists, skipping"
else
  echo "    Creating group: Viewers"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Viewers" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename viewer
fi

# Beginners group with beginner role (login only)
if /opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -q "\"name\" : \"Beginners\""; then
  echo "    Group 'Beginners' already exists, skipping"
else
  echo "    Creating group: Beginners"
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh create groups -r "${REALM}" -s name="Beginners" -i)
  /opt/keycloak/bin/kcadm.sh add-roles -r "${REALM}" --gid "${GROUP_ID}" --rolename beginner
fi

echo "==> Creating backend client..."
BACKEND_CLIENT_ID="backend-client"
if /opt/keycloak/bin/kcadm.sh get clients -r "${REALM}" --query "clientId=${BACKEND_CLIENT_ID}" | grep -q "\"clientId\" : \"${BACKEND_CLIENT_ID}\""; then
  echo "    Client '${BACKEND_CLIENT_ID}' already exists, skipping"
else
  /opt/keycloak/bin/kcadm.sh create clients -r "${REALM}" \
    -s clientId="${BACKEND_CLIENT_ID}" \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=false \
    -s directAccessGrantsEnabled=true \
    -s serviceAccountsEnabled=true \
    -s authorizationServicesEnabled=false \
    -s 'redirectUris=["*"]' \
    -s 'webOrigins=["*"]' \
    -s secret="${BACKEND_CLIENT_SECRET:-backend-secret-changeme}"
fi

echo "==> Creating frontend client..."
FRONTEND_CLIENT_ID="frontend-client"
if /opt/keycloak/bin/kcadm.sh get clients -r "${REALM}" --query "clientId=${FRONTEND_CLIENT_ID}" | grep -q "\"clientId\" : \"${FRONTEND_CLIENT_ID}\""; then
  echo "    Client '${FRONTEND_CLIENT_ID}' already exists, skipping"
else
  /opt/keycloak/bin/kcadm.sh create clients -r "${REALM}" \
    -s clientId="${FRONTEND_CLIENT_ID}" \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=true \
    -s directAccessGrantsEnabled=false \
    -s standardFlowEnabled=true \
    -s implicitFlowEnabled=false \
    -s 'redirectUris=["http://localhost:5173/*","https://localhost:3000/*","https://app.example.com/*","https://dr-app.example.com/*"]' \
    -s 'webOrigins=["+"]'
fi

echo "==> Creating sample users..."

# Admin user
ADMIN_USER="admin"
if /opt/keycloak/bin/kcadm.sh get users -r "${REALM}" --query "username=${ADMIN_USER}" | grep -q "\"username\" : \"${ADMIN_USER}\""; then
  echo "    User '${ADMIN_USER}' already exists, skipping"
else
  echo "    Creating admin user: ${ADMIN_USER}"
  ADMIN_USER_ID=$(/opt/keycloak/bin/kcadm.sh create users -r "${REALM}" \
    -s username="${ADMIN_USER}" \
    -s email="admin@example.com" \
    -s firstName="Admin" \
    -s lastName="User" \
    -s enabled=true \
    -s emailVerified=true \
    -i)
  
  /opt/keycloak/bin/kcadm.sh set-password -r "${REALM}" \
    --username "${ADMIN_USER}" \
    --new-password "admin123"
  
  # Add to Administrators group (roles inherited from group)
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -B1 "\"name\" : \"Administrators\"" | grep "\"id\"" | cut -d'"' -f4)
  if [ -n "$GROUP_ID" ]; then
    /opt/keycloak/bin/kcadm.sh update users/${ADMIN_USER_ID}/groups/${GROUP_ID} -r "${REALM}" -s realm="${REALM}" -s userId="${ADMIN_USER_ID}" -s groupId="${GROUP_ID}" -n 2>/dev/null || true
  fi
fi

# Test user
TEST_USER="testuser"
if /opt/keycloak/bin/kcadm.sh get users -r "${REALM}" --query "username=${TEST_USER}" | grep -q "\"username\" : \"${TEST_USER}\""; then
  echo "    User '${TEST_USER}' already exists, skipping"
else
  echo "    Creating test user: ${TEST_USER}"
  TEST_USER_ID=$(/opt/keycloak/bin/kcadm.sh create users -r "${REALM}" \
    -s username="${TEST_USER}" \
    -s email="test@example.com" \
    -s firstName="Test" \
    -s lastName="User" \
    -s enabled=true \
    -s emailVerified=true \
    -i)
  
  /opt/keycloak/bin/kcadm.sh set-password -r "${REALM}" \
    --username "${TEST_USER}" \
    --new-password "testpass123"
  
  # Add to Developers group (roles inherited from group)
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -B1 "\"name\" : \"Developers\"" | grep "\"id\"" | cut -d'"' -f4)
  if [ -n "$GROUP_ID" ]; then
    /opt/keycloak/bin/kcadm.sh update users/${TEST_USER_ID}/groups/${GROUP_ID} -r "${REALM}" -s realm="${REALM}" -s userId="${TEST_USER_ID}" -s groupId="${GROUP_ID}" -n 2>/dev/null || true
  fi
fi

# Manager user
MANAGER_USER="manager"
if /opt/keycloak/bin/kcadm.sh get users -r "${REALM}" --query "username=${MANAGER_USER}" | grep -q "\"username\" : \"${MANAGER_USER}\""; then
  echo "    User '${MANAGER_USER}' already exists, skipping"
else
  echo "    Creating manager user: ${MANAGER_USER}"
  MANAGER_USER_ID=$(/opt/keycloak/bin/kcadm.sh create users -r "${REALM}" \
    -s username="${MANAGER_USER}" \
    -s email="manager@example.com" \
    -s firstName="Manager" \
    -s lastName="User" \
    -s enabled=true \
    -s emailVerified=true \
    -i)
  
  /opt/keycloak/bin/kcadm.sh set-password -r "${REALM}" \
    --username "${MANAGER_USER}" \
    --new-password "manager123"
  
  # Add to Managers group (roles inherited from group)
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -B1 "\"name\" : \"Managers\"" | grep "\"id\"" | cut -d'"' -f4)
  if [ -n "$GROUP_ID" ]; then
    /opt/keycloak/bin/kcadm.sh update users/${MANAGER_USER_ID}/groups/${GROUP_ID} -r "${REALM}" -s realm="${REALM}" -s userId="${MANAGER_USER_ID}" -s groupId="${GROUP_ID}" -n 2>/dev/null || true
  fi
fi

# Viewer user
VIEWER_USER="viewer"
if /opt/keycloak/bin/kcadm.sh get users -r "${REALM}" --query "username=${VIEWER_USER}" | grep -q "\"username\" : \"${VIEWER_USER}\""; then
  echo "    User '${VIEWER_USER}' already exists, skipping"
else
  echo "    Creating viewer user: ${VIEWER_USER}"
  VIEWER_USER_ID=$(/opt/keycloak/bin/kcadm.sh create users -r "${REALM}" \
    -s username="${VIEWER_USER}" \
    -s email="viewer@example.com" \
    -s firstName="Viewer" \
    -s lastName="User" \
    -s enabled=true \
    -s emailVerified=true \
    -i)
  
  /opt/keycloak/bin/kcadm.sh set-password -r "${REALM}" \
    --username "${VIEWER_USER}" \
    --new-password "viewer123"
  
  # Add to Viewers group (roles inherited from group)
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -B1 "\"name\" : \"Viewers\"" | grep "\"id\"" | cut -d'"' -f4)
  if [ -n "$GROUP_ID" ]; then
    /opt/keycloak/bin/kcadm.sh update users/${VIEWER_USER_ID}/groups/${GROUP_ID} -r "${REALM}" -s realm="${REALM}" -s userId="${VIEWER_USER_ID}" -s groupId="${GROUP_ID}" -n 2>/dev/null || true
  fi
fi

# Beginner user
BEGINNER_USER="beginner"
if /opt/keycloak/bin/kcadm.sh get users -r "${REALM}" --query "username=${BEGINNER_USER}" | grep -q "\"username\" : \"${BEGINNER_USER}\""; then
  echo "    User '${BEGINNER_USER}' already exists, skipping"
else
  echo "    Creating beginner user: ${BEGINNER_USER}"
  BEGINNER_USER_ID=$(/opt/keycloak/bin/kcadm.sh create users -r "${REALM}" \
    -s username="${BEGINNER_USER}" \
    -s email="beginner@example.com" \
    -s firstName="Beginner" \
    -s lastName="User" \
    -s enabled=true \
    -s emailVerified=true \
    -i)
  
  /opt/keycloak/bin/kcadm.sh set-password -r "${REALM}" \
    --username "${BEGINNER_USER}" \
    --new-password "beginner123"
  
  # Add to Beginners group (roles inherited from group)
  GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r "${REALM}" | grep -B1 "\"name\" : \"Beginners\"" | grep "\"id\"" | cut -d'"' -f4)
  if [ -n "$GROUP_ID" ]; then
    /opt/keycloak/bin/kcadm.sh update users/${BEGINNER_USER_ID}/groups/${GROUP_ID} -r "${REALM}" -s realm="${REALM}" -s userId="${BEGINNER_USER_ID}" -s groupId="${GROUP_ID}" -n 2>/dev/null || true
  fi
fi

echo "==> Configuring user profile attributes..."
# Add custom attributes to users if needed
# This is a placeholder for future profile customizations

echo ""
echo "=========================================="
echo "Keycloak Realm Setup Complete!"
echo "=========================================="
echo ""
echo "Realm: ${REALM}"
echo "URL: https://localhost:8443/realms/${REALM}"
echo ""
echo "Sample Users:"
echo "  - admin@example.com     (admin/admin123)         [group: Administrators → roles: admin, manager]"
echo "  - test@example.com      (testuser/testpass123)   [group: Developers → roles: user, editor]"
echo "  - manager@example.com   (manager/manager123)     [group: Managers → roles: manager, user]"
echo "  - viewer@example.com    (viewer/viewer123)       [group: Viewers → roles: viewer]"
echo "  - beginner@example.com  (beginner/beginner123)   [group: Beginners → roles: beginner]"
echo ""
echo "Groups (with assigned roles):"
echo "  - Administrators → admin, manager"
echo "  - Developers → user, editor"
echo "  - Managers → manager, user"
echo "  - Operations → user"
echo "  - Viewers → viewer"
echo "  - Beginners → beginner (login only)"
echo ""
echo "Groups:"
echo "  - Administrators"
echo "  - Developers"
echo "  - Managers"
echo "  - Operations"
echo "  - Viewers"
echo "  - Beginners"
echo ""
echo "=========================================="
echo "Keycloak Realm Setup Complete!"
echo "=========================================="
echo ""
echo "Realm: ${REALM}"
echo "URL: https://localhost:8443/realms/${REALM}"
echo ""
echo "Sample Users:"
echo "  - admin@example.com     (admin/admin123)      [roles: admin, user]"
echo "  - test@example.com      (testuser/testpass123) [roles: user]"
echo "  - manager@example.com   (manager/manager123)   [roles: manager, user]"
echo "  - viewer@example.com    (viewer/viewer123)     [roles: viewer]"
echo ""
echo "Clients:"
echo "  - backend-client  (confidential)"
echo "  - frontend-client (public)"
echo ""
echo "=========================================="
