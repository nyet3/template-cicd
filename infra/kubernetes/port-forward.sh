#!/bin/bash
set -e

# Port forwarding script for Kubernetes services
# This script sets up port forwarding for all services in the template-cicd namespace

NAMESPACE="template-cicd"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
BACKEND_PORT="${BACKEND_PORT:-8080}"
KEYCLOAK_PORT="${KEYCLOAK_PORT:-8443}"

echo "🚀 Setting up port forwarding for $NAMESPACE namespace..."
echo "=================================================="

# Function to cleanup port forwards on exit
cleanup() {
    echo ""
    echo "🛑 Stopping port forwarding..."
    pkill -f "kubectl port-forward.*$NAMESPACE" 2>/dev/null || true
    echo "✅ Port forwarding stopped"
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "❌ Namespace '$NAMESPACE' not found"
    exit 1
fi

# Check if services are running
echo "📋 Checking services..."
if ! kubectl get service -n $NAMESPACE &> /dev/null; then
    echo "❌ No services found in namespace '$NAMESPACE'"
    exit 1
fi

# Kill any existing port forwards for this namespace
pkill -f "kubectl port-forward.*$NAMESPACE" 2>/dev/null || true
sleep 1

# Start port forwarding for frontend
echo "🌐 Forwarding frontend: https://localhost:$FRONTEND_PORT"
kubectl port-forward -n $NAMESPACE service/frontend $FRONTEND_PORT:443 > /tmp/k8s-pf-frontend.log 2>&1 &
FRONTEND_PID=$!

# Start port forwarding for backend
echo "🔧 Forwarding backend: http://localhost:$BACKEND_PORT"
kubectl port-forward -n $NAMESPACE service/backend $BACKEND_PORT:8080 > /tmp/k8s-pf-backend.log 2>&1 &
BACKEND_PID=$!

# Start port forwarding for keycloak
echo "🔐 Forwarding keycloak: https://localhost:$KEYCLOAK_PORT"
kubectl port-forward -n $NAMESPACE service/keycloak $KEYCLOAK_PORT:8443 > /tmp/k8s-pf-keycloak.log 2>&1 &
KEYCLOAK_PID=$!

# Wait a moment for port forwards to establish
sleep 2

# Verify port forwards are running
if ! ps -p $FRONTEND_PID > /dev/null 2>&1; then
    echo "❌ Frontend port forward failed. Check /tmp/k8s-pf-frontend.log"
    cleanup
fi

if ! ps -p $BACKEND_PID > /dev/null 2>&1; then
    echo "❌ Backend port forward failed. Check /tmp/k8s-pf-backend.log"
    cleanup
fi

if ! ps -p $KEYCLOAK_PID > /dev/null 2>&1; then
    echo "❌ Keycloak port forward failed. Check /tmp/k8s-pf-keycloak.log"
    cleanup
fi

echo ""
echo "✅ Port forwarding is active!"
echo "=================================================="
echo "📍 Access URLs:"
echo "   Frontend:  https://localhost:$FRONTEND_PORT"
echo "   Backend:   http://localhost:$BACKEND_PORT"
echo "   Keycloak:  https://localhost:$KEYCLOAK_PORT"
echo ""
echo "⚠️  Self-signed certificates are in use"
echo "   Accept the security warnings in your browser"
echo ""
echo "Press Ctrl+C to stop port forwarding"
echo "=================================================="

# Wait indefinitely (until Ctrl+C)
wait
