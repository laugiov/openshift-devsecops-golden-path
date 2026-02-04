#!/usr/bin/env bash
#
# bootstrap-service.sh - Create a new service from Golden Path template
#
# Usage:
#   ./scripts/bootstrap-service.sh my-service
#   ./scripts/bootstrap-service.sh my-service --interactive
#
# This script:
#   1. Creates service directory from template
#   2. Generates Helm chart in gitops/apps/
#   3. Creates environment values (dev/qa/prod)
#   4. Registers Argo CD applications
#   5. Optionally creates initial Jenkins job

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="${PROJECT_ROOT}/templates/service-template"

# Default configuration
DEFAULT_PORT=3000
DEFAULT_REGISTRY="172.23.0.5:5000"
DEFAULT_GITOPS_REPO="https://github.com/acme/openshift-devsecops-golden-path.git"
DEFAULT_BUILD_TOOL="docker"

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") <service-name> [options]

Create a new service from the Golden Path template.

Arguments:
    service-name    Name of the service (lowercase, hyphenated)

Options:
    -i, --interactive   Interactive mode - prompts for all options
    -p, --port PORT     Service port (default: ${DEFAULT_PORT})
    -r, --registry URL  Container registry URL (default: ${DEFAULT_REGISTRY})
    -t, --team NAME     Team name for metadata
    -e, --email EMAIL   Team email for metadata
    -d, --description   Service description
    -h, --help          Show this help message

Examples:
    $(basename "$0") payment-service
    $(basename "$0") payment-service --interactive
    $(basename "$0") user-api -p 8080 -t "Platform Team" -e platform@acme.com

Generated structure:
    services/<service-name>/         Application code + Jenkinsfile
    gitops/apps/<service-name>/      Helm chart
    gitops/env/dev/values-<name>.yaml    Environment-specific values
    gitops/env/qa/values-<name>.yaml
    gitops/env/prod/values-<name>.yaml
EOF
}

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Validate service name
validate_service_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        log_error "Invalid service name: $name"
        log_error "Must be lowercase, start with letter, use hyphens only"
        exit 1
    fi
    if [[ ${#name} -gt 53 ]]; then
        log_error "Service name too long (max 53 characters for K8s compatibility)"
        exit 1
    fi
}

# Interactive prompt
prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="${3:-}"
    local value

    if [[ -n "$default_value" ]]; then
        read -rp "$prompt_text [$default_value]: " value
        value="${value:-$default_value}"
    else
        read -rp "$prompt_text: " value
    fi

    eval "$var_name=\"$value\""
}

# Replace placeholders in file
replace_placeholders() {
    local file="$1"
    local service_name="$2"

    sed -i.bak \
        -e "s|{{SERVICE_NAME}}|${service_name}|g" \
        -e "s|{{SERVICE_PORT}}|${SERVICE_PORT}|g" \
        -e "s|{{REGISTRY_URL}}|${REGISTRY_URL}|g" \
        -e "s|{{GITOPS_REPO}}|${GITOPS_REPO}|g" \
        -e "s|{{BUILD_TOOL}}|${BUILD_TOOL}|g" \
        -e "s|{{TEAM_NAME}}|${TEAM_NAME}|g" \
        -e "s|{{TEAM_EMAIL}}|${TEAM_EMAIL}|g" \
        -e "s|{{SERVICE_DESCRIPTION}}|${SERVICE_DESCRIPTION}|g" \
        -e "s|{{SONARQUBE_ENABLED}}|${SONARQUBE_ENABLED}|g" \
        -e "s|{{SONAR_PROJECT_KEY}}|${SONAR_PROJECT_KEY}|g" \
        -e "s|{{SLACK_CHANNEL}}|${SLACK_CHANNEL}|g" \
        "$file"

    rm -f "${file}.bak"
}

# Create service application code
create_service_app() {
    local service_name="$1"
    local target_dir="${PROJECT_ROOT}/services/${service_name}"

    log_info "Creating service application in ${target_dir}..."

    mkdir -p "${target_dir}/src"

    # Copy and process templates
    cp "${TEMPLATE_DIR}/Jenkinsfile" "${target_dir}/"
    cp "${TEMPLATE_DIR}/Dockerfile" "${target_dir}/"
    cp "${TEMPLATE_DIR}/package.json" "${target_dir}/"
    cp "${TEMPLATE_DIR}/src/index.js" "${target_dir}/src/"

    # Replace placeholders
    for file in "${target_dir}/Jenkinsfile" "${target_dir}/Dockerfile" "${target_dir}/package.json" "${target_dir}/src/index.js"; do
        replace_placeholders "$file" "$service_name"
    done

    # Create .gitignore
    cat > "${target_dir}/.gitignore" << 'EOF'
node_modules/
.env
.env.local
*.log
coverage/
dist/
.DS_Store
EOF

    log_success "Service application created"
}

# Create Helm chart in gitops
create_helm_chart() {
    local service_name="$1"
    local chart_dir="${PROJECT_ROOT}/gitops/apps/${service_name}"

    log_info "Creating Helm chart in ${chart_dir}..."

    mkdir -p "${chart_dir}/templates"

    # Copy and process Helm templates
    cp "${TEMPLATE_DIR}/helm/Chart.yaml" "${chart_dir}/"
    cp "${TEMPLATE_DIR}/helm/values.yaml" "${chart_dir}/"
    cp "${TEMPLATE_DIR}/helm/templates/"* "${chart_dir}/templates/"

    # Replace placeholders in all files
    for file in "${chart_dir}/Chart.yaml" "${chart_dir}/values.yaml" "${chart_dir}/templates/"*; do
        replace_placeholders "$file" "$service_name"
    done

    log_success "Helm chart created"
}

# Create environment-specific values
create_env_values() {
    local service_name="$1"

    log_info "Creating environment values files..."

    # DEV values
    cat > "${PROJECT_ROOT}/gitops/env/dev/values-${service_name}.yaml" << EOF
# Development Environment Values for ${service_name}
# Auto-deployed on every successful build

replicaCount: 1

image:
  repository: ${REGISTRY_URL}/${service_name}
  tag: "latest"
  digest: ""

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: ${service_name}.dev.local
      paths:
        - path: /
          pathType: Prefix

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 50m
    memory: 64Mi

env:
  NODE_ENV: development
  LOG_LEVEL: debug

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 5

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 3
  periodSeconds: 5
EOF

    # QA values
    cat > "${PROJECT_ROOT}/gitops/env/qa/values-${service_name}.yaml" << EOF
# QA Environment Values for ${service_name}
# Promoted via PR from dev

replicaCount: 2

image:
  repository: ${REGISTRY_URL}/${service_name}
  tag: ""
  digest: ""  # Set by promotion PR

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: ${service_name}.qa.local
      paths:
        - path: /
          pathType: Prefix

resources:
  limits:
    cpu: 300m
    memory: 384Mi
  requests:
    cpu: 100m
    memory: 128Mi

env:
  NODE_ENV: qa
  LOG_LEVEL: info

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
EOF

    # PROD values
    cat > "${PROJECT_ROOT}/gitops/env/prod/values-${service_name}.yaml" << EOF
# Production Environment Values for ${service_name}
# Promoted via PR from qa - requires approval

replicaCount: 3

image:
  repository: ${REGISTRY_URL}/${service_name}
  tag: ""
  digest: ""  # MUST use digest for immutability

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "100"
  hosts:
    - host: ${service_name}.prod.local
      paths:
        - path: /
          pathType: Prefix

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi

env:
  NODE_ENV: production
  LOG_LEVEL: warn

livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: true
  minAvailable: 2
EOF

    log_success "Environment values created"
}

# Create Argo CD Application manifests
create_argocd_apps() {
    local service_name="$1"
    local apps_dir="${PROJECT_ROOT}/gitops/app-of-apps/templates"

    log_info "Creating Argo CD Application manifests..."

    # DEV Application (auto-sync)
    cat > "${apps_dir}/${service_name}-dev.yaml" << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${service_name}-dev
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${service_name}
    app.kubernetes.io/environment: dev
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: {{ .Values.gitops.repoURL }}
    targetRevision: {{ .Values.gitops.targetRevision | default "HEAD" }}
    path: gitops/apps/${service_name}
    helm:
      valueFiles:
        - ../../env/dev/values-${service_name}.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: ${service_name}-dev

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

    # QA Application (manual sync)
    cat > "${apps_dir}/${service_name}-qa.yaml" << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${service_name}-qa
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${service_name}
    app.kubernetes.io/environment: qa
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: {{ .Values.gitops.repoURL }}
    targetRevision: {{ .Values.gitops.targetRevision | default "HEAD" }}
    path: gitops/apps/${service_name}
    helm:
      valueFiles:
        - ../../env/qa/values-${service_name}.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: ${service_name}-qa

  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
EOF

    # PROD Application (manual sync, approval required)
    cat > "${apps_dir}/${service_name}-prod.yaml" << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${service_name}-prod
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${service_name}
    app.kubernetes.io/environment: prod
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: {{ .Values.gitops.repoURL }}
    targetRevision: {{ .Values.gitops.targetRevision | default "HEAD" }}
    path: gitops/apps/${service_name}
    helm:
      valueFiles:
        - ../../env/prod/values-${service_name}.yaml

  destination:
    server: https://kubernetes.default.svc
    namespace: ${service_name}-prod

  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
EOF

    log_success "Argo CD Applications created"
}

# Print next steps
print_next_steps() {
    local service_name="$1"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Service ${service_name} created!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Generated structure:"
    echo "  services/${service_name}/           Application code"
    echo "  gitops/apps/${service_name}/        Helm chart"
    echo "  gitops/env/*/values-${service_name}.yaml  Environment values"
    echo "  gitops/app-of-apps/templates/${service_name}-*.yaml  Argo CD apps"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated code in services/${service_name}/"
    echo "  2. Customize the Jenkinsfile parameters if needed"
    echo "  3. Commit and push:"
    echo "     git add services/${service_name} gitops/"
    echo "     git commit -m 'Add ${service_name} service'"
    echo "     git push"
    echo ""
    echo "  4. Sync Argo CD app-of-apps to register the new service:"
    echo "     argocd app sync golden-path-apps"
    echo ""
    echo "  5. Trigger first build in Jenkins"
    echo ""
    echo "For more information, see: docs/ONBOARDING.md"
}

# Main function
main() {
    # Parse arguments
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi

    local service_name=""
    local interactive=false

    # Initialize defaults
    SERVICE_PORT="${DEFAULT_PORT}"
    REGISTRY_URL="${DEFAULT_REGISTRY}"
    GITOPS_REPO="${DEFAULT_GITOPS_REPO}"
    BUILD_TOOL="${DEFAULT_BUILD_TOOL}"
    TEAM_NAME="ACME Team"
    TEAM_EMAIL="team@acme.com"
    SERVICE_DESCRIPTION="A microservice"
    SONARQUBE_ENABLED="true"
    SONAR_PROJECT_KEY=""
    SLACK_CHANNEL="#builds"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -p|--port)
                SERVICE_PORT="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY_URL="$2"
                shift 2
                ;;
            -t|--team)
                TEAM_NAME="$2"
                shift 2
                ;;
            -e|--email)
                TEAM_EMAIL="$2"
                shift 2
                ;;
            -d|--description)
                SERVICE_DESCRIPTION="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$service_name" ]]; then
                    service_name="$1"
                else
                    log_error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate service name
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        show_help
        exit 1
    fi
    validate_service_name "$service_name"

    # Check for existing service
    if [[ -d "${PROJECT_ROOT}/services/${service_name}" ]]; then
        log_error "Service ${service_name} already exists"
        exit 1
    fi

    # Interactive mode
    if [[ "$interactive" == "true" ]]; then
        echo ""
        echo -e "${BLUE}=== Golden Path Service Bootstrap ===${NC}"
        echo ""
        prompt SERVICE_PORT "Service port" "${SERVICE_PORT}"
        prompt REGISTRY_URL "Container registry URL" "${REGISTRY_URL}"
        prompt TEAM_NAME "Team name" "${TEAM_NAME}"
        prompt TEAM_EMAIL "Team email" "${TEAM_EMAIL}"
        prompt SERVICE_DESCRIPTION "Service description" "${SERVICE_DESCRIPTION}"
        prompt BUILD_TOOL "Build tool (docker/maven/gradle/npm)" "${BUILD_TOOL}"

        read -rp "Enable SonarQube quality gate? [Y/n]: " sonar_answer
        if [[ "${sonar_answer,,}" == "n" ]]; then
            SONARQUBE_ENABLED="false"
        fi

        prompt SLACK_CHANNEL "Slack channel for notifications" "${SLACK_CHANNEL}"
        echo ""
    fi

    # Set derived values
    SONAR_PROJECT_KEY="${service_name}"

    # Create all components
    log_info "Creating service: ${service_name}"
    echo ""

    create_service_app "$service_name"
    create_helm_chart "$service_name"
    create_env_values "$service_name"
    create_argocd_apps "$service_name"

    print_next_steps "$service_name"
}

# Run main
main "$@"
