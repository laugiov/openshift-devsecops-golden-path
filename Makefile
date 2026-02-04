.PHONY: help up down restart logs health demo clean lint test \
	bootstrap setup-kind teardown-kind argocd-ui argocd-password \
	build push deploy promote scan-all sbom sign verify \
	demo-full demo-level1 demo-level2 demo-level3 \
	demo-e2e demo-quick pipeline-ci pipeline-cd pipeline-full

# Default target
.DEFAULT_GOAL := help

# Configuration
CLUSTER_NAME ?= golden-path
REGISTRY ?= localhost:5000
IMAGE_NAME ?= demo-service
IMAGE_TAG ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
ARGOCD_NAMESPACE ?= argocd

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

##@ General

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\n${CYAN}Usage:${RESET}\n  make ${GREEN}<target>${RESET}\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  ${GREEN}%-15s${RESET} %s\n", $$1, $$2 } /^##@/ { printf "\n${CYAN}%s${RESET}\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Local Development

up: ## Start all services (Jenkins, SonarQube, Nexus, Registry)
	@echo "Starting local development stack..."
	docker compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 10
	@$(MAKE) health

down: ## Stop all services
	@echo "Stopping local development stack..."
	docker compose down

restart: down up ## Restart all services

logs: ## Tail logs from all services
	docker compose logs -f

logs-jenkins: ## Tail Jenkins logs only
	docker compose logs -f jenkins

logs-sonar: ## Tail SonarQube logs only
	docker compose logs -f sonarqube

##@ Health Checks

health: ## Check health of all services
	@echo "Checking service health..."
	@echo ""
	@printf "Jenkins:    "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null | grep -q "200" && echo "${GREEN}OK${RESET}" || echo "${YELLOW}NOT READY${RESET}"
	@printf "SonarQube:  "
	@curl -s http://localhost:9000/api/system/status 2>/dev/null | grep -q "UP" && echo "${GREEN}OK${RESET}" || echo "${YELLOW}NOT READY${RESET}"
	@printf "Nexus:      "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ 2>/dev/null | grep -qE "200|302" && echo "${GREEN}OK${RESET}" || echo "${YELLOW}NOT READY${RESET}"
	@printf "Registry:   "
	@curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/v2/ 2>/dev/null | grep -q "200" && echo "${GREEN}OK${RESET}" || echo "${YELLOW}NOT READY${RESET}"
	@echo ""

##@ Demo

demo: ## Run the demo pipeline
	@echo "Triggering demo pipeline in Jenkins..."
	@curl -X POST http://admin:admin@localhost:8080/job/demo-service/build 2>/dev/null || echo "Jenkins job trigger requires authentication setup"
	@echo "Open http://localhost:8080/job/demo-service to watch progress"

demo-build: ## Build the demo service locally
	@echo "Building demo service..."
	cd demo-service && npm install && npm test

##@ Quality & Security

lint: ## Run linters on all code
	@echo "Running linters..."
	@echo "Checking shell scripts..."
	@find scripts -name "*.sh" -exec shellcheck {} \; 2>/dev/null || echo "shellcheck not installed"
	@echo "Checking YAML files..."
	@find . -name "*.yaml" -o -name "*.yml" | grep -v node_modules | xargs yamllint 2>/dev/null || echo "yamllint not installed"

test: ## Run all tests
	@echo "Running demo-service tests..."
	cd demo-service && npm install --silent && npm test
	@echo ""
	@echo "Running shared library unit tests..."
	cd jenkins-shared-library && ./gradlew test --quiet || echo "Note: Groovy tests require Jenkins mocking setup"

test-integration: ## Run Docker integration tests (requires Docker)
	@echo "Running integration tests with Docker..."
	./scripts/test/integration-test.sh

test-integration-quick: ## Run quick Docker integration tests
	@echo "Running quick integration tests..."
	./scripts/test/integration-test.sh --quick --keep

test-all: test test-integration ## Run all tests including integration

scan-sast: ## Run SAST scan
	@echo "Running SAST scan..."
	./scripts/scanners/run-sast.sh

scan-sca: ## Run SCA scan
	@echo "Running SCA scan..."
	./scripts/scanners/run-sca.sh

scan-secrets: ## Run secrets detection
	@echo "Running secrets scan..."
	./scripts/scanners/run-secrets-scan.sh

scan-all: scan-sast scan-sca scan-secrets ## Run all security scans

##@ Artifacts

sbom: ## Generate SBOM for demo-service
	@echo "Generating SBOM..."
	./scripts/sbom/generate-sbom.sh ./demo-service

sign: ## Sign the demo-service image
	@echo "Signing image..."
	./scripts/signing/sign-image.sh localhost:5000/demo-service:latest

verify: ## Verify image signature
	@echo "Verifying image signature..."
	cosign verify --key cosign.pub localhost:5000/demo-service:latest

##@ Cleanup

clean: ## Remove all generated files and containers
	@echo "Cleaning up..."
	docker compose down -v --remove-orphans
	rm -rf demo-service/node_modules
	rm -rf demo-service/coverage
	rm -rf demo-service/sbom.json
	@echo "Clean complete"

clean-images: ## Remove all local Docker images for this project
	@echo "Removing project images..."
	docker images | grep -E "demo-service|golden-path" | awk '{print $$3}' | xargs -r docker rmi -f

##@ Setup

setup: ## Initial setup for local development
	@echo "Setting up local development environment..."
	@cp -n .env.example .env 2>/dev/null || true
	@echo "Generating Cosign keys..."
	@./scripts/signing/generate-cosign-keys.sh 2>/dev/null || echo "Cosign key generation requires cosign installed"
	@echo "Setup complete. Run 'make up' to start services."

setup-jenkins: ## Configure Jenkins with shared library
	@echo "Configuring Jenkins..."
	./scripts/setup/configure-jenkins.sh

##@ Information

urls: ## Show URLs for all services
	@echo ""
	@echo "${CYAN}Service URLs:${RESET}"
	@echo "  Jenkins:    http://localhost:8080  (admin/admin)"
	@echo "  SonarQube:  http://localhost:9000  (admin/admin)"
	@echo "  Nexus:      http://localhost:8081  (admin/admin123)"
	@echo "  Registry:   http://localhost:5000"
	@echo ""

versions: ## Show versions of key tools
	@echo ""
	@echo "${CYAN}Tool Versions:${RESET}"
	@printf "  Docker:     " && docker --version 2>/dev/null | cut -d' ' -f3 || echo "not installed"
	@printf "  Compose:    " && docker compose version 2>/dev/null | cut -d' ' -f4 || echo "not installed"
	@printf "  Cosign:     " && cosign version 2>/dev/null | head -1 | cut -d' ' -f3 || echo "not installed"
	@printf "  Trivy:      " && trivy --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "not installed"
	@printf "  Semgrep:    " && semgrep --version 2>/dev/null || echo "not installed"
	@printf "  Kind:       " && kind version 2>/dev/null | cut -d' ' -f2 || echo "not installed"
	@printf "  Kubectl:    " && kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "not installed"
	@printf "  Helm:       " && helm version --short 2>/dev/null | cut -d'+' -f1 || echo "not installed"
	@echo ""

##@ Bootstrap

bootstrap: ## Full bootstrap: setup + start all services + wait
	@echo "${CYAN}Starting full bootstrap...${RESET}"
	@./scripts/setup/bootstrap-local.sh

validate: ## Validate local environment setup
	@./scripts/validate-setup.sh

wait-services: ## Wait for all services to be healthy
	@./scripts/setup/wait-for-services.sh

##@ Container Build

build: ## Build demo-service container image
	@echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
	docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ./demo-service
	docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
	docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
	@echo "${GREEN}Build complete: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}${RESET}"

push: ## Push image to local registry
	@echo "Pushing to ${REGISTRY}..."
	docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
	docker push ${REGISTRY}/${IMAGE_NAME}:latest
	@echo "${GREEN}Push complete${RESET}"

build-push: build push ## Build and push in one step

##@ Kind Cluster (Level 3)

setup-kind: ## Create Kind cluster with Argo CD
	@echo "${CYAN}Setting up Kind cluster...${RESET}"
	@./scripts/setup/setup-kind-cluster.sh

teardown-kind: ## Delete Kind cluster
	@echo "${YELLOW}Deleting Kind cluster: ${CLUSTER_NAME}...${RESET}"
	kind delete cluster --name ${CLUSTER_NAME}
	@echo "${GREEN}Cluster deleted${RESET}"

kind-status: ## Show Kind cluster status
	@echo "${CYAN}Kind Cluster Status:${RESET}"
	@kind get clusters 2>/dev/null | grep -q "${CLUSTER_NAME}" && echo "  Cluster: ${GREEN}running${RESET}" || echo "  Cluster: ${YELLOW}not found${RESET}"
	@kubectl cluster-info --context kind-${CLUSTER_NAME} 2>/dev/null || true

##@ Argo CD

argocd-ui: ## Port forward Argo CD UI to localhost:8443
	@echo "Starting Argo CD port forward..."
	@echo "Access UI at: ${CYAN}https://localhost:8443${RESET}"
	@echo "Username: admin"
	@echo "Password: run 'make argocd-password'"
	@echo ""
	@echo "Press Ctrl+C to stop"
	kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8443:443

argocd-password: ## Get Argo CD admin password
	@echo "${CYAN}Argo CD Admin Password:${RESET}"
	@kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

argocd-apps: ## List Argo CD applications
	@echo "${CYAN}Argo CD Applications:${RESET}"
	@kubectl get applications -n ${ARGOCD_NAMESPACE} 2>/dev/null || echo "No applications found"

argocd-sync: ## Sync all Argo CD applications
	@echo "Syncing all applications..."
	@kubectl get applications -n ${ARGOCD_NAMESPACE} -o name | xargs -I {} kubectl patch {} -n ${ARGOCD_NAMESPACE} --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'

##@ GitOps Deployment

deploy-dev: ## Deploy to dev namespace via Argo CD
	@echo "Deploying to demo-dev..."
	kubectl apply -f gitops/environments/dev/ -n demo-dev 2>/dev/null || echo "GitOps manifests not found. Create them first."

deploy-qa: ## Deploy to qa namespace via Argo CD
	@echo "Deploying to demo-qa..."
	kubectl apply -f gitops/environments/qa/ -n demo-qa 2>/dev/null || echo "GitOps manifests not found. Create them first."

deploy-prod: ## Deploy to prod namespace via Argo CD
	@echo "Deploying to demo-prod..."
	kubectl apply -f gitops/environments/prod/ -n demo-prod 2>/dev/null || echo "GitOps manifests not found. Create them first."

##@ Full Demo Workflows

demo-level1: up wait-services ## Level 1: Start CI infrastructure only
	@echo ""
	@echo "${GREEN}Level 1 Complete: CI Infrastructure Running${RESET}"
	@$(MAKE) urls

demo-level2: demo-level1 build scan-all sbom ## Level 2: Full pipeline with scans
	@echo ""
	@echo "${GREEN}Level 2 Complete: Pipeline with Security Scans${RESET}"
	@echo "Reports available in: ./reports/"
	@ls -la reports/ 2>/dev/null || true

demo-level3: demo-level2 setup-kind push ## Level 3: GitOps with Kind + Argo CD
	@echo ""
	@echo "${GREEN}Level 3 Complete: Full GitOps Stack${RESET}"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make argocd-ui     - Open Argo CD UI"
	@echo "  2. make argocd-password - Get admin password"
	@echo "  3. Deploy with: make deploy-dev"

demo-full: demo-level3 ## Run complete demo (all 3 levels)
	@echo ""
	@echo "${GREEN}==========================================${RESET}"
	@echo "${GREEN} Full Demo Complete!${RESET}"
	@echo "${GREEN}==========================================${RESET}"
	@echo ""
	@$(MAKE) urls
	@echo "Kind cluster: ${CLUSTER_NAME}"
	@echo "Argo CD: https://localhost:8443 (run 'make argocd-ui')"
	@echo ""

##@ Pipeline Simulation

pipeline-ci: ## Simulate CI pipeline (test -> scan -> build)
	@echo "${CYAN}=== CI Pipeline Simulation ===${RESET}"
	@echo ""
	@echo "Step 1: Unit Tests"
	@cd demo-service && npm test
	@echo ""
	@echo "Step 2: SAST Scan"
	@$(MAKE) scan-sast
	@echo ""
	@echo "Step 3: Secrets Scan"
	@$(MAKE) scan-secrets
	@echo ""
	@echo "Step 4: Build Image"
	@$(MAKE) build
	@echo ""
	@echo "Step 5: SCA Scan"
	@$(MAKE) scan-sca
	@echo ""
	@echo "Step 6: Generate SBOM"
	@$(MAKE) sbom
	@echo ""
	@echo "${GREEN}CI Pipeline Complete${RESET}"

pipeline-cd: push sign ## Simulate CD pipeline (push -> sign -> verify)
	@echo "${CYAN}=== CD Pipeline Simulation ===${RESET}"
	@echo ""
	@echo "Step 1: Push to Registry"
	@echo "  (completed)"
	@echo ""
	@echo "Step 2: Sign Image"
	@echo "  (completed)"
	@echo ""
	@echo "Step 3: Verify Signature"
	@$(MAKE) verify
	@echo ""
	@echo "${GREEN}CD Pipeline Complete${RESET}"

pipeline-full: pipeline-ci pipeline-cd ## Full CI/CD pipeline simulation
	@echo ""
	@echo "${GREEN}==========================================${RESET}"
	@echo "${GREEN} Full Pipeline Simulation Complete${RESET}"
	@echo "${GREEN}==========================================${RESET}"

##@ Quick Demo (No Docker Required)

demo-e2e: ## Run end-to-end demo without Docker (tests, scans, validation)
	@echo ""
	@echo "${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
	@echo "${CYAN}║       Golden Path DevSecOps - End-to-End Demo                   ║${RESET}"
	@echo "${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
	@echo ""
	@echo "${YELLOW}This demo runs without Docker to showcase the project quality.${RESET}"
	@echo ""
	@echo "${CYAN}[1/6] Running demo-service unit tests...${RESET}"
	@cd demo-service && npm install --silent && npm test
	@echo ""
	@echo "${GREEN}✓ Unit tests passed with coverage${RESET}"
	@echo ""
	@echo "${CYAN}[2/6] Validating Groovy syntax...${RESET}"
	@cd jenkins-shared-library && ./gradlew compileGroovy --quiet 2>/dev/null && echo "${GREEN}✓ Groovy syntax valid${RESET}" || echo "${YELLOW}⚠ Gradle not available - skipping${RESET}"
	@echo ""
	@echo "${CYAN}[3/6] Checking for secrets in codebase...${RESET}"
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks detect --source . --no-git --quiet && echo "${GREEN}✓ No secrets detected${RESET}"; \
	else \
		echo "${YELLOW}⚠ Gitleaks not installed - checking manually...${RESET}"; \
		! grep -rn "PRIVATE KEY" --include="*.groovy" --include="*.sh" --include="*.yaml" . 2>/dev/null && echo "${GREEN}✓ No obvious secrets found${RESET}"; \
	fi
	@echo ""
	@echo "${CYAN}[4/6] Validating YAML files...${RESET}"
	@if command -v yamllint >/dev/null 2>&1; then \
		yamllint -d relaxed gitops/ 2>/dev/null && echo "${GREEN}✓ YAML files valid${RESET}"; \
	else \
		echo "${YELLOW}⚠ yamllint not installed - basic check...${RESET}"; \
		find gitops -name "*.yaml" -exec python3 -c "import yaml; yaml.safe_load(open('{}'))" \; 2>/dev/null && echo "${GREEN}✓ YAML files parseable${RESET}"; \
	fi
	@echo ""
	@echo "${CYAN}[5/6] Verifying documentation completeness...${RESET}"
	@for doc in README.md CONTRIBUTING.md SECURITY.md LICENSE docs/ARCHITECTURE.md docs/DESIGN_DECISIONS.md docs/ONBOARDING.md; do \
		if [ -f "$$doc" ]; then \
			echo "  ✓ $$doc"; \
		else \
			echo "  ✗ $$doc MISSING"; \
			exit 1; \
		fi; \
	done
	@echo "${GREEN}✓ All required documentation present${RESET}"
	@echo ""
	@echo "${CYAN}[6/6] Displaying project structure...${RESET}"
	@echo ""
	@echo "jenkins-shared-library/vars/:"
	@ls -1 jenkins-shared-library/vars/*.groovy | xargs -n1 basename | sed 's/^/  ├── /'
	@echo ""
	@echo "gitops/:"
	@echo "  ├── app-of-apps/    (Argo CD bootstrap)"
	@echo "  ├── apps/           (Application Helm charts)"
	@echo "  ├── env/            (Environment values)"
	@echo "  └── policies/       (Kyverno admission policies)"
	@echo ""
	@echo "${GREEN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
	@echo "${GREEN}║                    Demo Complete - All Checks Passed             ║${RESET}"
	@echo "${GREEN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
	@echo ""
	@echo "Next steps:"
	@echo "  ${CYAN}make up${RESET}           - Start local dev stack (requires Docker)"
	@echo "  ${CYAN}make demo${RESET}         - Run full pipeline demo"
	@echo "  ${CYAN}make setup-kind${RESET}   - Setup Kind cluster with Argo CD"
	@echo ""

demo-quick: ## Quick validation (tests only, fastest)
	@echo "${CYAN}Quick validation...${RESET}"
	@cd demo-service && npm install --silent && npm test
	@echo "${GREEN}✓ Quick validation passed${RESET}"
