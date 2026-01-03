.PHONY: help dev test build clean docker-build docker-test k8s-deploy k8s-clean k8s-port-forward k8s-stop-port-forward k8s-status k8s-create-secrets certs certs-k8s certs-docker certs-clean keycloak-setup keycloak-setup-docker keycloak-setup-k8s keycloak-logs keycloak-reset keycloak-client-update

help:
	@echo "Available targets:"
	@echo "  dev                    - Start development environment"
	@echo "  test                   - Run all tests"
	@echo "  build                  - Build all components"
	@echo "  clean                  - Clean build artifacts"
	@echo ""
	@echo "Docker Compose:"
	@echo "  docker-build           - Build Docker images"
	@echo "  docker-test            - Run tests in Docker"
	@echo ""
	@echo "Kubernetes:"
	@echo "  k8s-deploy             - Complete K8s deployment (images, certs, deploy, port-forward)"
	@echo "  k8s-clean              - Clean up all K8s resources"
	@echo "  k8s-port-forward       - Start port forwarding for K8s services"
	@echo "  k8s-stop-port-forward  - Stop all port forwarding"
	@echo "  k8s-status             - Show status of all K8s resources"
	@echo "  k8s-create-secrets     - Create TLS secrets from existing certificates"
	@echo ""
	@echo "Certificates:"
	@echo "  certs                  - Generate all certificates (K8s + Docker)"
	@echo "  certs-k8s              - Generate Kubernetes certificates"
	@echo "  certs-docker           - Generate Docker Compose certificates"
	@echo "  certs-clean            - Remove all generated certificates"
	@echo ""
	@echo "Keycloak:"
	@echo "  keycloak-setup         - Setup Keycloak (auto-detect environment)"
	@echo "  keycloak-setup-docker  - Setup Keycloak in Docker Compose"
	@echo "  keycloak-setup-k8s     - Setup Keycloak in Kubernetes"
	@echo "  keycloak-logs          - Show Keycloak logs"
	@echo "  keycloak-reset         - Reset Keycloak data (use with caution)"
	@echo "  keycloak-client-update - Update Keycloak frontend client settings"

dev:
	@echo "Starting development environment..."
	@echo "Use VS Code F5 or run backend and frontend separately"

test:
	@echo "Running backend tests..."
	cd backend && cargo test
	@echo "Running frontend tests..."
	cd frontend && npm test

build:
	@echo "Building backend..."
	cd backend && cargo build --release
	@echo "Building frontend..."
	cd frontend && npm run build

clean:
	@echo "Cleaning..."
	cd backend && cargo clean
	cd frontend && rm -rf dist node_modules

docker-build:
	docker-compose build

docker-test:
	docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit

k8s-deploy:
	@echo "� Starting complete Kubernetes deployment..."
	@echo ""
	@echo "📦 Step 1: Creating namespace..."
	kubectl apply -f infra/kubernetes/namespace.yaml
	@echo "⏳ Waiting for namespace to be ready..."
	@sleep 2
	@echo ""
	@echo "🔐 Step 2: Generating TLS certificates..."
	@cd infra/kubernetes && ./generate-k8s-certs.sh
	@echo ""
	@echo "📝 Step 3: Creating TLS secrets..."
	@kubectl create secret tls frontend-tls \
		--cert=infra/kubernetes/k8s-certs/frontend.crt \
		--key=infra/kubernetes/k8s-certs/frontend.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret tls keycloak-tls \
		--cert=infra/kubernetes/k8s-certs/keycloak.crt \
		--key=infra/kubernetes/k8s-certs/keycloak.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "🐳 Step 4: Building Docker images in Minikube..."
	@echo "Building backend..."
	@eval $$(minikube docker-env) && docker build -t backend:latest -f infra/docker/backend.Dockerfile backend/
	@echo "Building frontend..."
	@eval $$(minikube docker-env) && docker build -t frontend:latest -f infra/docker/frontend.Dockerfile frontend/
	@echo ""
	@echo "📦 Step 5: Deploying Kubernetes resources..."
	kubectl apply -f infra/kubernetes/
	@echo ""
	@echo "⏳ Step 6: Waiting for pods to be ready..."
	@echo "Waiting for backend..."
	@kubectl wait --for=condition=ready pod -l app=backend -n template-cicd --timeout=120s || true
	@echo "Waiting for frontend..."
	@kubectl wait --for=condition=ready pod -l app=frontend -n template-cicd --timeout=120s || true
	@echo "Waiting for keycloak..."
	@kubectl wait --for=condition=ready pod -l app=keycloak -n template-cicd --timeout=180s || true
	@echo ""
	@echo "🔌 Step 7: Starting port forwarding..."
	@# Kill existing port-forward processes more carefully
	@ps aux | grep 'kubectl port-forward.*template-cicd' | grep -v grep | awk '{print $$2}' | xargs -r kill 2>/dev/null || true
	@sleep 2
	@# Create temporary script to fully detach port-forward
	@echo '#!/bin/bash' > /tmp/start-k8s-pf.sh
	@echo 'kubectl port-forward -n template-cicd service/frontend 3000:443 > /tmp/k8s-pf-frontend.log 2>&1 &' >> /tmp/start-k8s-pf.sh
	@echo 'kubectl port-forward -n template-cicd service/backend 8080:8080 > /tmp/k8s-pf-backend.log 2>&1 &' >> /tmp/start-k8s-pf.sh
	@echo 'kubectl port-forward -n template-cicd service/keycloak 8443:8443 > /tmp/k8s-pf-keycloak.log 2>&1 &' >> /tmp/start-k8s-pf.sh
	@chmod +x /tmp/start-k8s-pf.sh
	@nohup /tmp/start-k8s-pf.sh >/dev/null 2>&1 &
	@sleep 3
	@if pgrep -f "kubectl port-forward.*template-cicd" > /dev/null 2>&1; then \
		echo "✅ Port forwarding started successfully"; \
	else \
		echo "⚠️  Port forwarding may not have started"; \
		echo "   You can start it manually with: make k8s-port-forward"; \
	fi
	@echo ""
	@echo "✅ Deployment completed successfully!"
	@echo "=============================================="
	@echo "📍 Access URLs:"
	@echo "   Frontend:  https://localhost:3000"
	@echo "   Backend:   http://localhost:8080"
	@echo "   Keycloak:  https://localhost:8443"
	@echo ""
	@echo "👤 Test credentials:"
	@echo "   Username: testuser"
	@echo "   Password: testpass123"
	@echo ""
	@echo "⚠️  Accept self-signed certificate warnings in your browser"
	@echo "To stop port forwarding: make k8s-stop-port-forward"
	@echo "=============================================="

k8s-clean:
	@echo "🧹 Cleaning up Kubernetes resources..."
	@echo "Stopping port forwarding..."
	@pkill -f "kubectl port-forward.*template-cicd" 2>/dev/null || true
	@echo "Deleting namespace and all resources..."
	@kubectl delete namespace template-cicd --ignore-not-found=true
	@echo "✅ Cleanup completed"

k8s-port-forward:
	@echo "Starting port forwarding..."
	@./infra/kubernetes/port-forward.sh

k8s-stop-port-forward:
	@echo "Stopping port forwarding..."
	@pkill -f "kubectl port-forward.*template-cicd" || echo "No port forwarding processes found"

k8s-status:
	@echo "📊 Kubernetes Status - template-cicd namespace"
	@echo "=============================================="
	@echo ""
	@echo "📦 Pods:"
	@kubectl get pods -n template-cicd
	@echo ""
	@echo "🔧 Services:"
	@kubectl get services -n template-cicd
	@echo ""
	@echo "🔐 Secrets:"
	@kubectl get secrets -n template-cicd
	@echo ""
	@echo "📝 ConfigMaps:"
	@kubectl get configmaps -n template-cicd
	@echo ""
	@echo "🚀 Deployments:"
	@kubectl get deployments -n template-cicd
	@echo ""

k8s-create-secrets:
	@echo "🔐 Creating Kubernetes TLS secrets from existing certificates..."
	@if [ ! -f infra/kubernetes/k8s-certs/frontend.crt ]; then \
		echo "❌ Certificate files not found. Run 'make certs-k8s' first."; \
		exit 1; \
	fi
	@echo "📝 Creating frontend-tls secret..."
	@kubectl create secret tls frontend-tls \
		--cert=infra/kubernetes/k8s-certs/frontend.crt \
		--key=infra/kubernetes/k8s-certs/frontend.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@echo "📝 Creating keycloak-tls secret..."
	@kubectl create secret tls keycloak-tls \
		--cert=infra/kubernetes/k8s-certs/keycloak.crt \
		--key=infra/kubernetes/k8s-certs/keycloak.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@echo "✅ TLS secrets created successfully"


# Certificate generation targets
certs: certs-k8s certs-docker
	@echo "✅ All certificates generated successfully"

certs-k8s:
	@echo "🔐 Generating Kubernetes certificates..."
	@cd infra/kubernetes && ./generate-k8s-certs.sh
	@echo "📝 Creating Kubernetes TLS secrets..."
	@kubectl create secret tls frontend-tls \
		--cert=infra/kubernetes/k8s-certs/frontend.crt \
		--key=infra/kubernetes/k8s-certs/frontend.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret tls keycloak-tls \
		--cert=infra/kubernetes/k8s-certs/keycloak.crt \
		--key=infra/kubernetes/k8s-certs/keycloak.key \
		-n template-cicd --dry-run=client -o yaml | kubectl apply -f -
	@echo "✅ Kubernetes certificates and secrets created"

certs-docker:
	@echo "🔐 Generating Docker Compose certificates..."
	@mkdir -p frontend/certs
	@if [ ! -f frontend/certs/frontend.crt ] || [ ! -f frontend/certs/frontend.key ]; then \
		echo "📝 Generating frontend certificate..."; \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout frontend/certs/frontend.key \
			-out frontend/certs/frontend.crt \
			-subj "/C=JP/ST=Tokyo/L=Tokyo/O=Development/OU=Frontend/CN=localhost" \
			-addext "subjectAltName=DNS:localhost,DNS:frontend,IP:127.0.0.1" 2>/dev/null; \
		chmod 644 frontend/certs/frontend.crt; \
		chmod 600 frontend/certs/frontend.key; \
		echo "✅ Docker Compose certificates created"; \
	else \
		echo "⚠️  Docker Compose certificates already exist, skipping"; \
	fi

certs-clean:
	@echo "🧹 Cleaning up generated certificates..."
	@rm -rf infra/kubernetes/k8s-certs
	@rm -rf frontend/certs
	@echo "✅ All certificates removed"

# Keycloak setup targets
keycloak-setup:
	@echo "🔐 Detecting environment and setting up Keycloak..."
	@if docker ps --filter "name=template-cicd-keycloak" --format "{{.Names}}" | grep -q template-cicd-keycloak; then \
		echo "📦 Docker Compose environment detected"; \
		$(MAKE) keycloak-setup-docker; \
	elif kubectl get namespace template-cicd >/dev/null 2>&1; then \
		echo "☸️  Kubernetes environment detected"; \
		$(MAKE) keycloak-setup-k8s; \
	else \
		echo "❌ No Keycloak environment detected"; \
		echo "   Start with: docker compose up -d keycloak"; \
		echo "   Or deploy to K8s: make k8s-deploy"; \
		exit 1; \
	fi

keycloak-setup-docker:
	@echo "🔐 Setting up Keycloak in Docker Compose..."
	@if ! docker ps --filter "name=template-cicd-keycloak" --format "{{.Names}}" | grep -q template-cicd-keycloak; then \
		echo "⚠️  Keycloak container is not running"; \
		echo "   Starting Keycloak..."; \
		docker compose up -d keycloak; \
		echo "⏳ Waiting for Keycloak to start..."; \
		sleep 10; \
	fi
	@echo "📝 Running realm setup script..."
	@docker exec template-cicd-keycloak bash /opt/keycloak/bin/setup-realm.sh || \
		echo "⚠️  Setup script may have already run or failed. Check logs with: make keycloak-logs"
	@echo "✅ Keycloak setup completed"

keycloak-setup-k8s:
	@echo "🔐 Setting up Keycloak in Kubernetes..."
	@if ! kubectl get pod -n template-cicd -l app=keycloak | grep -q Running; then \
		echo "⚠️  Keycloak pod is not running"; \
		echo "   Deploy with: make k8s-deploy"; \
		exit 1; \
	fi
	@echo "📝 Running initial data setup script..."
	@KEYCLOAK_POD=$$(kubectl get pod -n template-cicd -l app=keycloak -o jsonpath='{.items[0].metadata.name}'); \
	kubectl port-forward -n template-cicd pod/$$KEYCLOAK_POD 8443:8443 > /tmp/kc-pf.log 2>&1 & \
	PF_PID=$$!; \
	sleep 2; \
	KEYCLOAK_URL=https://localhost:8443 bash infra/kubernetes/setup-keycloak-initial-data.sh; \
	kill $$PF_PID 2>/dev/null || true
	@echo "✅ Keycloak setup completed"

keycloak-logs:
	@echo "📋 Showing Keycloak logs..."
	@if docker ps --filter "name=template-cicd-keycloak" --format "{{.Names}}" | grep -q template-cicd-keycloak; then \
		echo "📦 Docker Compose logs:"; \
		docker logs template-cicd-keycloak --tail 50 -f; \
	elif kubectl get namespace template-cicd >/dev/null 2>&1; then \
		echo "☸️  Kubernetes logs:"; \
		kubectl logs -n template-cicd -l app=keycloak --tail 50 -f; \
	else \
		echo "❌ No Keycloak environment detected"; \
		exit 1; \
	fi

keycloak-reset:
	@echo "⚠️  WARNING: This will delete all Keycloak data!"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		if docker ps -a --filter "name=template-cicd-keycloak" --format "{{.Names}}" | grep -q template-cicd-keycloak; then \
			echo "📦 Resetting Docker Compose environment..."; \
			docker compose down -v; \
			docker compose up -d; \
			echo "⏳ Waiting for services to start..."; \
			sleep 10; \
			$(MAKE) keycloak-setup-docker; \
		elif kubectl get namespace template-cicd >/dev/null 2>&1; then \
			echo "☸️  Resetting Kubernetes environment..."; \
			kubectl delete pod -n template-cicd -l app=keycloak; \
			echo "⏳ Waiting for pod to restart..."; \
			kubectl wait --for=condition=ready pod -n template-cicd -l app=keycloak --timeout=60s; \
			$(MAKE) keycloak-setup-k8s; \
		else \
			echo "❌ No Keycloak environment detected"; \
			exit 1; \
		fi; \
		echo "✅ Keycloak reset completed"; \
	else \
		echo "❌ Reset cancelled"; \
	fi

keycloak-client-update:
	@echo "🔄 Updating Keycloak frontend client..."
	@if docker ps --filter "name=template-cicd-keycloak" --format "{{.Names}}" | grep -q template-cicd-keycloak; then \
		echo "📦 Updating in Docker Compose environment..."; \
		KEYCLOAK_URL=https://localhost:8443 \
		REALM=testrealm \
		CLIENT_ID=frontend-client \
		REDIRECT_URI="http://localhost:5173/*,http://localhost:3000/*,https://localhost:3000/*" \
		bash infra/kubernetes/setup-keycloak-client.sh; \
	elif kubectl get namespace template-cicd >/dev/null 2>&1; then \
		echo "☸️  Updating in Kubernetes environment..."; \
		KEYCLOAK_POD=$$(kubectl get pod -n template-cicd -l app=keycloak -o jsonpath='{.items[0].metadata.name}'); \
		kubectl port-forward -n template-cicd pod/$$KEYCLOAK_POD 8443:8443 > /tmp/kc-pf.log 2>&1 & \
		PF_PID=$$!; \
		sleep 2; \
		KEYCLOAK_URL=https://localhost:8443 \
		REALM=testrealm \
		CLIENT_ID=frontend-client \
		REDIRECT_URI="http://localhost:5173/*,http://localhost:3000/*,https://localhost:3000/*" \
		bash infra/kubernetes/setup-keycloak-client.sh; \
		kill $$PF_PID 2>/dev/null || true; \
	else \
		echo "❌ No Keycloak environment detected"; \
		exit 1; \
	fi
	@echo "✅ Client update completed"

