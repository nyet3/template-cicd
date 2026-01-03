.PHONY: help dev test build clean docker-build docker-test k8s-deploy k8s-clean k8s-port-forward k8s-stop-port-forward k8s-status k8s-create-secrets certs certs-k8s certs-docker certs-clean keycloak-setup keycloak-setup-docker keycloak-setup-k8s keycloak-logs keycloak-reset keycloak-client-update aws-login aws-ecr-push aws-eks-deploy aws-eks-status aws-eks-clean aws-ecs-deploy aws-ecs-status aws-ecs-clean prod-deploy prod-status prod-clean multi-region-init multi-region-plan multi-region-apply multi-region-status multi-region-destroy

# AWS Configuration
AWS_REGION_PRIMARY ?= ap-northeast-1
AWS_REGION_SECONDARY ?= ap-northeast-3
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
ECR_REGISTRY_PRIMARY ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION_PRIMARY).amazonaws.com
ECR_REGISTRY_SECONDARY ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION_SECONDARY).amazonaws.com
ECR_REPO_BACKEND ?= template-cicd/backend
ECR_REPO_FRONTEND ?= template-cicd/frontend
IMAGE_TAG ?= $(shell git rev-parse --short HEAD)

# Legacy single-region support
AWS_REGION ?= $(AWS_REGION_PRIMARY)
ECR_REGISTRY ?= $(ECR_REGISTRY_PRIMARY)

# EKS Configuration
EKS_CLUSTER_NAME_PRIMARY ?= template-cicd-cluster-apne1
EKS_CLUSTER_NAME_SECONDARY ?= template-cicd-cluster-oska
EKS_NAMESPACE ?= template-cicd

# Legacy single-region support
EKS_CLUSTER_NAME ?= $(EKS_CLUSTER_NAME_PRIMARY)

# ECS Configuration
ECS_CLUSTER_NAME ?= template-cicd-cluster
ECS_SERVICE_BACKEND ?= template-cicd-backend
ECS_SERVICE_FRONTEND ?= template-cicd-frontend
ECS_TASK_FAMILY_BACKEND ?= template-cicd-backend
ECS_TASK_FAMILY_FRONTEND ?= template-cicd-frontend

# Deployment target (eks or ecs)
DEPLOY_TARGET ?= eks

# Multi-region Terraform directory
TERRAFORM_DIR ?= infra/terraform/multi-region

help:
	@echo "Available targets:"
	@echo "  dev                    - Start development environment"
	@echo "  test                   - Run all tests"
	@echo "  build                  - Build all components"
	@echo "  clean                  - Clean build artifacts"
	@echo ""
	@echo "Docker Compose (Staging):"
	@echo "  docker-build           - Build Docker images"
	@echo "  docker-test            - Run tests in Docker"
	@echo ""
	@echo "Minikube/K8s (Staging):"
	@echo "  k8s-deploy             - Complete K8s deployment (images, certs, deploy, port-forward)"
	@echo "  k8s-clean              - Clean up all K8s resources"
	@echo "  k8s-port-forward       - Start port forwarding for K8s services"
	@echo "  k8s-stop-port-forward  - Stop all port forwarding"
	@echo "  k8s-status             - Show status of all K8s resources"
	@echo "  k8s-create-secrets     - Create TLS secrets from existing certificates"
	@echo ""
	@echo "AWS Production:"
	@echo "  aws-login              - Login to AWS ECR"
	@echo "  aws-ecr-push           - Build and push images to ECR"
	@echo "  aws-eks-deploy         - Deploy to EKS cluster"
	@echo "  aws-eks-status         - Show EKS deployment status"
	@echo "  aws-eks-clean          - Clean up EKS resources"
	@echo "  aws-ecs-deploy         - Deploy to ECS Fargate"
	@echo "  aws-ecs-status         - Show ECS deployment status"
	@echo "  aws-ecs-clean          - Clean up ECS resources"
	@echo "  prod-deploy            - Deploy to production (DEPLOY_TARGET=eks|ecs)"
	@echo "  prod-status            - Show production deployment status"
	@echo "  prod-clean             - Clean up production resources"
	@echo ""
	@echo "Multi-Region Disaster Recovery:"
	@echo "  multi-region-init      - Initialize Terraform for multi-region deployment"
	@echo "  multi-region-plan      - Plan multi-region infrastructure changes"
	@echo "  multi-region-apply     - Apply multi-region infrastructure"
	@echo "  multi-region-status    - Show status of both regions"
	@echo "  multi-region-destroy   - Destroy multi-region infrastructure"
	@echo ""
	@echo "Environment Variables:"
	@echo "  AWS_REGION_PRIMARY=$(AWS_REGION_PRIMARY)"
	@echo "  AWS_REGION_SECONDARY=$(AWS_REGION_SECONDARY)"
	@echo "  AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID)"
	@echo "  ECR_REGISTRY_PRIMARY=$(ECR_REGISTRY_PRIMARY)"
	@echo "  IMAGE_TAG=$(IMAGE_TAG)"
	@echo "  DEPLOY_TARGET=$(DEPLOY_TARGET)"
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

# =============================================================================
# AWS Production Deployment
# =============================================================================

aws-login:
	@echo "🔐 Logging into AWS ECR..."
	@if [ -z "$(AWS_ACCOUNT_ID)" ]; then \
		echo "❌ AWS_ACCOUNT_ID is not set. Make sure AWS CLI is configured."; \
		exit 1; \
	fi
	@aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_REGISTRY)
	@echo "✅ Logged in to ECR: $(ECR_REGISTRY)"

aws-ecr-push: aws-login
	@echo "🐳 Building and pushing images to ECR..."
	@echo ""
	@echo "📦 Building backend image..."
	docker build -t $(ECR_REPO_BACKEND):$(IMAGE_TAG) \
		-t $(ECR_REPO_BACKEND):latest \
		-f infra/docker/backend.Dockerfile backend/
	@echo "📤 Tagging and pushing backend..."
	docker tag $(ECR_REPO_BACKEND):$(IMAGE_TAG) $(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG)
	docker tag $(ECR_REPO_BACKEND):latest $(ECR_REGISTRY)/$(ECR_REPO_BACKEND):latest
	docker push $(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG)
	docker push $(ECR_REGISTRY)/$(ECR_REPO_BACKEND):latest
	@echo ""
	@echo "📦 Building frontend image..."
	docker build -t $(ECR_REPO_FRONTEND):$(IMAGE_TAG) \
		-t $(ECR_REPO_FRONTEND):latest \
		-f infra/docker/frontend.Dockerfile frontend/ \
		--build-arg VITE_API_URL="" \
		--build-arg VITE_AUTH_ENABLED=true \
		--build-arg VITE_OIDC_AUTHORITY="https://keycloak.yourdomain.com/realms/testrealm" \
		--build-arg VITE_OIDC_CLIENT_ID="frontend-client" \
		--build-arg VITE_OIDC_REDIRECT_URI="https://app.yourdomain.com/callback"
	@echo "📤 Tagging and pushing frontend..."
	docker tag $(ECR_REPO_FRONTEND):$(IMAGE_TAG) $(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG)
	docker tag $(ECR_REPO_FRONTEND):latest $(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):latest
	docker push $(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG)
	docker push $(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):latest
	@echo ""
	@echo "✅ Images pushed to ECR"
	@echo "   Backend:  $(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG)"
	@echo "   Frontend: $(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG)"

aws-eks-deploy: aws-ecr-push
	@echo "☸️  Deploying to EKS cluster: $(EKS_CLUSTER_NAME)"
	@echo ""
	@echo "📝 Updating kubeconfig..."
	@aws eks update-kubeconfig --region $(AWS_REGION) --name $(EKS_CLUSTER_NAME)
	@echo ""
	@echo "📦 Creating namespace..."
	@kubectl create namespace $(EKS_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "🔐 Creating secrets..."
	@kubectl create secret docker-registry ecr-registry \
		--docker-server=$(ECR_REGISTRY) \
		--docker-username=AWS \
		--docker-password=$$(aws ecr get-login-password --region $(AWS_REGION)) \
		-n $(EKS_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "📝 Applying Kubernetes manifests..."
	@kubectl apply -f infra/kubernetes/namespace.yaml
	@kubectl apply -f infra/kubernetes/secrets.yaml
	@kubectl apply -f infra/kubernetes/configmap.yaml
	@echo ""
	@echo "🔄 Updating image tags in deployments..."
	@kubectl set image deployment/backend backend=$(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG) -n $(EKS_NAMESPACE) || \
		(kubectl apply -f infra/kubernetes/backend.yaml && \
		 kubectl set image deployment/backend backend=$(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG) -n $(EKS_NAMESPACE))
	@kubectl set image deployment/frontend frontend=$(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG) -n $(EKS_NAMESPACE) || \
		(kubectl apply -f infra/kubernetes/frontend.yaml && \
		 kubectl set image deployment/frontend frontend=$(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG) -n $(EKS_NAMESPACE))
	@kubectl apply -f infra/kubernetes/keycloak.yaml
	@kubectl apply -f infra/kubernetes/ingress.yaml
	@echo ""
	@echo "⏳ Waiting for rollout to complete..."
	@kubectl rollout status deployment/backend -n $(EKS_NAMESPACE) --timeout=300s || true
	@kubectl rollout status deployment/frontend -n $(EKS_NAMESPACE) --timeout=300s || true
	@kubectl rollout status deployment/keycloak -n $(EKS_NAMESPACE) --timeout=300s || true
	@echo ""
	@echo "✅ EKS deployment completed!"
	@echo "=============================================="
	@$(MAKE) aws-eks-status

aws-eks-status:
	@echo "📊 EKS Deployment Status - $(EKS_CLUSTER_NAME)/$(EKS_NAMESPACE)"
	@echo "=============================================="
	@echo ""
	@echo "📦 Pods:"
	@kubectl get pods -n $(EKS_NAMESPACE) -o wide || echo "No pods found"
	@echo ""
	@echo "🔧 Services:"
	@kubectl get services -n $(EKS_NAMESPACE) || echo "No services found"
	@echo ""
	@echo "🌐 Ingress:"
	@kubectl get ingress -n $(EKS_NAMESPACE) || echo "No ingress found"
	@echo ""
	@echo "🚀 Deployments:"
	@kubectl get deployments -n $(EKS_NAMESPACE) || echo "No deployments found"
	@echo ""
	@INGRESS_URL=$$(kubectl get ingress -n $(EKS_NAMESPACE) -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -n "$$INGRESS_URL" ]; then \
		echo "🌐 Application URL: https://$$INGRESS_URL"; \
	fi

aws-eks-clean:
	@echo "🧹 Cleaning up EKS resources..."
	@read -p "Are you sure you want to delete all resources in $(EKS_NAMESPACE)? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		aws eks update-kubeconfig --region $(AWS_REGION) --name $(EKS_CLUSTER_NAME); \
		kubectl delete namespace $(EKS_NAMESPACE) --ignore-not-found=true; \
		echo "✅ EKS cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

aws-ecs-deploy: aws-ecr-push
	@echo "🐳 Deploying to ECS Fargate: $(ECS_CLUSTER_NAME)"
	@echo ""
	@echo "📝 Registering backend task definition..."
	@aws ecs register-task-definition \
		--family $(ECS_TASK_FAMILY_BACKEND) \
		--network-mode awsvpc \
		--requires-compatibilities FARGATE \
		--cpu 256 \
		--memory 512 \
		--execution-role-arn arn:aws:iam::$(AWS_ACCOUNT_ID):role/ecsTaskExecutionRole \
		--container-definitions '[{ \
			"name": "backend", \
			"image": "$(ECR_REGISTRY)/$(ECR_REPO_BACKEND):$(IMAGE_TAG)", \
			"essential": true, \
			"portMappings": [{"containerPort": 8080, "protocol": "tcp"}], \
			"environment": [ \
				{"name": "ENVIRONMENT", "value": "production"}, \
				{"name": "SERVER_HOST", "value": "0.0.0.0"}, \
				{"name": "SERVER_PORT", "value": "8080"}, \
				{"name": "RUST_LOG", "value": "info"} \
			], \
			"logConfiguration": { \
				"logDriver": "awslogs", \
				"options": { \
					"awslogs-group": "/ecs/$(ECS_TASK_FAMILY_BACKEND)", \
					"awslogs-region": "$(AWS_REGION)", \
					"awslogs-stream-prefix": "ecs" \
				} \
			} \
		}]' > /dev/null
	@echo ""
	@echo "📝 Registering frontend task definition..."
	@aws ecs register-task-definition \
		--family $(ECS_TASK_FAMILY_FRONTEND) \
		--network-mode awsvpc \
		--requires-compatibilities FARGATE \
		--cpu 256 \
		--memory 512 \
		--execution-role-arn arn:aws:iam::$(AWS_ACCOUNT_ID):role/ecsTaskExecutionRole \
		--container-definitions '[{ \
			"name": "frontend", \
			"image": "$(ECR_REGISTRY)/$(ECR_REPO_FRONTEND):$(IMAGE_TAG)", \
			"essential": true, \
			"portMappings": [{"containerPort": 443, "protocol": "tcp"}], \
			"environment": [ \
				{"name": "ENVIRONMENT", "value": "production"} \
			], \
			"logConfiguration": { \
				"logDriver": "awslogs", \
				"options": { \
					"awslogs-group": "/ecs/$(ECS_TASK_FAMILY_FRONTEND)", \
					"awslogs-region": "$(AWS_REGION)", \
					"awslogs-stream-prefix": "ecs" \
				} \
			} \
		}]' > /dev/null
	@echo ""
	@echo "🔄 Updating backend service..."
	@aws ecs update-service \
		--cluster $(ECS_CLUSTER_NAME) \
		--service $(ECS_SERVICE_BACKEND) \
		--task-definition $(ECS_TASK_FAMILY_BACKEND) \
		--force-new-deployment > /dev/null || \
		echo "⚠️  Service $(ECS_SERVICE_BACKEND) not found. Please create it via AWS Console or Terraform."
	@echo ""
	@echo "🔄 Updating frontend service..."
	@aws ecs update-service \
		--cluster $(ECS_CLUSTER_NAME) \
		--service $(ECS_SERVICE_FRONTEND) \
		--task-definition $(ECS_TASK_FAMILY_FRONTEND) \
		--force-new-deployment > /dev/null || \
		echo "⚠️  Service $(ECS_SERVICE_FRONTEND) not found. Please create it via AWS Console or Terraform."
	@echo ""
	@echo "✅ ECS deployment initiated!"
	@echo "=============================================="
	@$(MAKE) aws-ecs-status

aws-ecs-status:
	@echo "📊 ECS Deployment Status - $(ECS_CLUSTER_NAME)"
	@echo "=============================================="
	@echo ""
	@echo "🔧 Backend Service:"
	@aws ecs describe-services \
		--cluster $(ECS_CLUSTER_NAME) \
		--services $(ECS_SERVICE_BACKEND) \
		--query 'services[0].[serviceName,status,runningCount,desiredCount]' \
		--output table 2>/dev/null || echo "Service not found"
	@echo ""
	@echo "🌐 Frontend Service:"
	@aws ecs describe-services \
		--cluster $(ECS_CLUSTER_NAME) \
		--services $(ECS_SERVICE_FRONTEND) \
		--query 'services[0].[serviceName,status,runningCount,desiredCount]' \
		--output table 2>/dev/null || echo "Service not found"
	@echo ""
	@echo "📦 Recent Task Statuses:"
	@aws ecs list-tasks --cluster $(ECS_CLUSTER_NAME) --max-items 5 \
		--query 'taskArns[]' --output text 2>/dev/null | \
		xargs -I {} aws ecs describe-tasks --cluster $(ECS_CLUSTER_NAME) --tasks {} \
		--query 'tasks[].[taskArn,lastStatus,healthStatus]' --output table 2>/dev/null || \
		echo "No tasks found"

aws-ecs-clean:
	@echo "🧹 Cleaning up ECS resources..."
	@read -p "Are you sure you want to stop all services in $(ECS_CLUSTER_NAME)? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "🛑 Updating backend service to 0 tasks..."; \
		aws ecs update-service \
			--cluster $(ECS_CLUSTER_NAME) \
			--service $(ECS_SERVICE_BACKEND) \
			--desired-count 0 > /dev/null 2>&1 || true; \
		echo "🛑 Updating frontend service to 0 tasks..."; \
		aws ecs update-service \
			--cluster $(ECS_CLUSTER_NAME) \
			--service $(ECS_SERVICE_FRONTEND) \
			--desired-count 0 > /dev/null 2>&1 || true; \
		echo "✅ ECS cleanup completed"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Unified production deployment commands
prod-deploy:
	@if [ "$(DEPLOY_TARGET)" = "eks" ]; then \
		$(MAKE) aws-eks-deploy; \
	elif [ "$(DEPLOY_TARGET)" = "ecs" ]; then \
		$(MAKE) aws-ecs-deploy; \
	else \
		echo "❌ Invalid DEPLOY_TARGET: $(DEPLOY_TARGET)"; \
		echo "   Use: make prod-deploy DEPLOY_TARGET=eks"; \
		echo "   Or:  make prod-deploy DEPLOY_TARGET=ecs"; \
		exit 1; \
	fi

prod-status:
	@if [ "$(DEPLOY_TARGET)" = "eks" ]; then \
		$(MAKE) aws-eks-status; \
	elif [ "$(DEPLOY_TARGET)" = "ecs" ]; then \
		$(MAKE) aws-ecs-status; \
	else \
		echo "❌ Invalid DEPLOY_TARGET: $(DEPLOY_TARGET)"; \
		exit 1; \
	fi

prod-clean:
	@if [ "$(DEPLOY_TARGET)" = "eks" ]; then \
		$(MAKE) aws-eks-clean; \
	elif [ "$(DEPLOY_TARGET)" = "ecs" ]; then \
		$(MAKE) aws-ecs-clean; \
	else \
		echo "❌ Invalid DEPLOY_TARGET: $(DEPLOY_TARGET)"; \
		exit 1; \
	fi

# Multi-Region Disaster Recovery Commands
multi-region-init:
	@echo "🌍 Initializing Terraform for multi-region deployment..."
	@cd $(TERRAFORM_DIR) && terraform init
	@echo "✅ Terraform initialized successfully"

multi-region-plan:
	@echo "🌍 Planning multi-region infrastructure changes..."
	@cd $(TERRAFORM_DIR) && terraform plan
	@echo "✅ Terraform plan completed"

multi-region-apply:
	@echo "🌍 Applying multi-region infrastructure..."
	@echo "⚠️  This will deploy to both $(AWS_REGION_PRIMARY) and $(AWS_REGION_SECONDARY)"
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd $(TERRAFORM_DIR) && terraform apply -auto-approve; \
		echo "✅ Multi-region infrastructure deployed successfully"; \
	else \
		echo "❌ Deployment cancelled"; \
	fi

multi-region-status:
	@echo "🌍 Multi-Region Status"
	@echo "=============================================="
	@echo ""
	@echo "📍 Primary Region: $(AWS_REGION_PRIMARY)"
	@echo "--------------------------------------------"
	@echo "EKS Clusters:"
	@aws eks describe-cluster --region $(AWS_REGION_PRIMARY) --name $(EKS_CLUSTER_NAME_PRIMARY) \
		--query 'cluster.[name,status,endpoint]' --output table 2>/dev/null || echo "No cluster found"
	@echo ""
	@echo "Load Balancers:"
	@aws elbv2 describe-load-balancers --region $(AWS_REGION_PRIMARY) \
		--query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
		--output table 2>/dev/null || echo "No load balancers found"
	@echo ""
	@echo "Aurora Clusters:"
	@aws rds describe-db-clusters --region $(AWS_REGION_PRIMARY) \
		--query 'DBClusters[?contains(DBClusterIdentifier, `template-cicd`)].{Identifier:DBClusterIdentifier,Status:Status,Endpoint:Endpoint}' \
		--output table 2>/dev/null || echo "No Aurora clusters found"
	@echo ""
	@echo "=============================================="
	@echo "📍 Secondary Region: $(AWS_REGION_SECONDARY)"
	@echo "--------------------------------------------"
	@echo "EKS Clusters:"
	@aws eks describe-cluster --region $(AWS_REGION_SECONDARY) --name $(EKS_CLUSTER_NAME_SECONDARY) \
		--query 'cluster.[name,status,endpoint]' --output table 2>/dev/null || echo "No cluster found"
	@echo ""
	@echo "Load Balancers:"
	@aws elbv2 describe-load-balancers --region $(AWS_REGION_SECONDARY) \
		--query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}' \
		--output table 2>/dev/null || echo "No load balancers found"
	@echo ""
	@echo "Aurora Clusters:"
	@aws rds describe-db-clusters --region $(AWS_REGION_SECONDARY) \
		--query 'DBClusters[?contains(DBClusterIdentifier, `template-cicd`)].{Identifier:DBClusterIdentifier,Status:Status,Endpoint:Endpoint}' \
		--output table 2>/dev/null || echo "No Aurora clusters found"
	@echo ""
	@echo "=============================================="
	@echo "🏥 Route53 Health Checks:"
	@aws route53 list-health-checks \
		--query 'HealthChecks[?contains(to_string(Tags), `template-cicd`)].{ID:Id,Domain:HealthCheckConfig.FullyQualifiedDomainName,Status:HealthCheckConfig.Type}' \
		--output table 2>/dev/null || echo "No health checks found"

multi-region-destroy:
	@echo "🌍 Destroying multi-region infrastructure..."
	@echo "⚠️  WARNING: This will destroy ALL resources in both regions!"
	@echo "   Primary:   $(AWS_REGION_PRIMARY)"
	@echo "   Secondary: $(AWS_REGION_SECONDARY)"
	@read -p "Type 'destroy-all' to confirm: " confirm; \
	if [ "$$confirm" = "destroy-all" ]; then \
		cd $(TERRAFORM_DIR) && terraform destroy -auto-approve; \
		echo "✅ Multi-region infrastructure destroyed"; \
	else \
		echo "❌ Destroy cancelled"; \
	fi

# Deploy application to both regions
multi-region-deploy-app:
	@echo "🌍 Deploying application to both regions..."
	@echo ""
	@echo "📍 Deploying to Primary Region ($(AWS_REGION_PRIMARY))..."
	@aws eks update-kubeconfig --region $(AWS_REGION_PRIMARY) --name $(EKS_CLUSTER_NAME_PRIMARY)
	@kubectl apply -f infra/kubernetes/namespace.yaml
	@kubectl apply -f infra/kubernetes/configmap.yaml
	@kubectl apply -f infra/kubernetes/secrets.yaml
	@kubectl apply -f infra/kubernetes/backend.yaml
	@kubectl apply -f infra/kubernetes/frontend.yaml
	@kubectl apply -f infra/kubernetes/keycloak.yaml
	@kubectl rollout status deployment/backend -n $(EKS_NAMESPACE) --timeout=5m
	@kubectl rollout status deployment/frontend -n $(EKS_NAMESPACE) --timeout=5m
	@echo "✅ Primary region deployment completed"
	@echo ""
	@echo "📍 Deploying to Secondary Region ($(AWS_REGION_SECONDARY))..."
	@aws eks update-kubeconfig --region $(AWS_REGION_SECONDARY) --name $(EKS_CLUSTER_NAME_SECONDARY)
	@kubectl apply -f infra/kubernetes/namespace.yaml
	@kubectl apply -f infra/kubernetes/configmap.yaml
	@kubectl apply -f infra/kubernetes/secrets.yaml
	@kubectl apply -f infra/kubernetes/backend.yaml
	@kubectl apply -f infra/kubernetes/frontend.yaml
	@kubectl apply -f infra/kubernetes/keycloak.yaml
	@kubectl rollout status deployment/backend -n $(EKS_NAMESPACE) --timeout=5m
	@kubectl rollout status deployment/frontend -n $(EKS_NAMESPACE) --timeout=5m
	@echo "✅ Secondary region deployment completed"
	@echo ""
	@echo "✅ Application deployed to both regions successfully!"
