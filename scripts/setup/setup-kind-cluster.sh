#!/bin/bash
set -euo pipefail

# Set up Kind cluster with Argo CD for GitOps testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CLUSTER_NAME=${CLUSTER_NAME:-golden-path}
ARGOCD_NAMESPACE="argocd"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    if ! command -v kind &> /dev/null; then
        missing+=("kind")
    fi

    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing+=("helm")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install kind kubectl helm"
        exit 1
    fi

    log_success "Prerequisites OK"
}

create_cluster() {
    log_info "Creating Kind cluster: ${CLUSTER_NAME}..."

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster '${CLUSTER_NAME}' already exists"
        read -p "Delete and recreate? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "${CLUSTER_NAME}"
        else
            log_info "Using existing cluster"
            return 0
        fi
    fi

    kind create cluster \
        --config "${PROJECT_ROOT}/kind-config.yaml" \
        --name "${CLUSTER_NAME}"

    log_success "Cluster created"
}

connect_registry() {
    log_info "Connecting local registry to Kind network..."

    # Check if registry is running
    if ! docker ps | grep -q "golden-path-registry"; then
        log_warn "Local registry not running. Start with 'make up' first."
        return 0
    fi

    # Connect registry to kind network if not already connected
    if ! docker network inspect kind | grep -q "golden-path-registry"; then
        docker network connect kind golden-path-registry 2>/dev/null || true
        log_success "Registry connected to Kind network"
    else
        log_info "Registry already connected"
    fi

    # Create configmap for local registry
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:5000"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

    log_success "Registry configuration applied"
}

install_ingress() {
    log_info "Installing NGINX Ingress controller..."

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    log_info "Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s

    log_success "Ingress controller ready"
}

install_argocd() {
    log_info "Installing Argo CD..."

    # Create namespace
    kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Install Argo CD
    kubectl apply -n "${ARGOCD_NAMESPACE}" \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log_info "Waiting for Argo CD to be ready..."
    kubectl wait --namespace "${ARGOCD_NAMESPACE}" \
        --for=condition=available deployment/argocd-server \
        --timeout=300s

    log_success "Argo CD installed"

    # Get initial admin password
    local admin_password
    admin_password=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    echo ""
    log_success "Argo CD is ready!"
    echo ""
    echo "Access Argo CD:"
    echo "  1. Port forward: kubectl port-forward svc/argocd-server -n argocd 8443:443"
    echo "  2. Open: https://localhost:8443"
    echo "  3. Login: admin / ${admin_password}"
    echo ""
}

create_namespaces() {
    log_info "Creating environment namespaces..."

    for env in dev qa prod; do
        kubectl create namespace "demo-${env}" --dry-run=client -o yaml | kubectl apply -f -
        log_success "Created namespace: demo-${env}"
    done
}

setup_argocd_app() {
    log_info "Setting up Argo CD application..."

    # Apply the app-of-apps
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: golden-path-apps
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: https://github.com/example/openshift-devsecops-golden-path.git
    targetRevision: HEAD
    path: gitops/app-of-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

    log_warn "Note: Update the repoURL above to your actual repository"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo " Kind Cluster Setup Complete"
    echo "=========================================="
    echo ""
    echo "Cluster: ${CLUSTER_NAME}"
    echo ""
    echo "Namespaces:"
    echo "  - demo-dev"
    echo "  - demo-qa"
    echo "  - demo-prod"
    echo ""
    echo "Access Argo CD:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
    echo "  Open: https://localhost:8443"
    echo ""
    echo "Push images to local registry:"
    echo "  docker tag myimage localhost:5000/myimage:tag"
    echo "  docker push localhost:5000/myimage:tag"
    echo ""
    echo "Delete cluster when done:"
    echo "  kind delete cluster --name ${CLUSTER_NAME}"
    echo ""
}

main() {
    echo ""
    echo "=========================================="
    echo " Kind + Argo CD Setup"
    echo "=========================================="
    echo ""

    check_prerequisites
    echo ""
    create_cluster
    echo ""
    connect_registry
    echo ""
    install_ingress
    echo ""
    install_argocd
    echo ""
    create_namespaces
    echo ""
    # setup_argocd_app  # Commented out - requires real repo URL
    print_summary
}

main "$@"
