#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi

    if ! command -v docker compose &> /dev/null; then
        # Try older docker-compose
        if ! command -v docker-compose &> /dev/null; then
            missing+=("docker-compose")
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Please install the missing tools:"
        echo "  - Docker: https://docs.docker.com/get-docker/"
        echo "  - Docker Compose: included with Docker Desktop"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# Check optional tools
check_optional_tools() {
    log_info "Checking optional tools..."

    if command -v cosign &> /dev/null; then
        log_success "cosign found: $(cosign version 2>&1 | head -1)"
    else
        log_warn "cosign not found - image signing will not work"
        echo "  Install: brew install cosign (macOS) or see https://docs.sigstore.dev/cosign/installation/"
    fi

    if command -v trivy &> /dev/null; then
        log_success "trivy found: $(trivy --version 2>&1 | head -1)"
    else
        log_warn "trivy not found - SCA scanning will use container"
        echo "  Install: brew install trivy (macOS) or see https://aquasecurity.github.io/trivy/"
    fi

    if command -v semgrep &> /dev/null; then
        log_success "semgrep found: $(semgrep --version 2>&1)"
    else
        log_warn "semgrep not found - SAST scanning will use container"
        echo "  Install: pip install semgrep or brew install semgrep"
    fi

    if command -v helm &> /dev/null; then
        log_success "helm found: $(helm version --short 2>&1)"
    else
        log_warn "helm not found - GitOps testing will not work"
        echo "  Install: brew install helm (macOS) or see https://helm.sh/docs/intro/install/"
    fi

    if command -v kind &> /dev/null; then
        log_success "kind found: $(kind version 2>&1)"
    else
        log_warn "kind not found - local Kubernetes testing will not work"
        echo "  Install: brew install kind (macOS) or see https://kind.sigs.k8s.io/"
    fi

    if command -v kubectl &> /dev/null; then
        log_success "kubectl found: $(kubectl version --client -o yaml 2>&1 | grep gitVersion | awk '{print $2}')"
    else
        log_warn "kubectl not found - Kubernetes interactions will not work"
        echo "  Install: brew install kubectl (macOS)"
    fi
}

# Create .env file
setup_env() {
    log_info "Setting up environment file..."

    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        log_warn ".env file already exists, skipping"
        return
    fi

    cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
    log_success "Created .env file from .env.example"
    log_warn "Review and update .env with your values"
}

# Generate Cosign keys
setup_cosign_keys() {
    log_info "Setting up Cosign signing keys..."

    if [[ -f "${PROJECT_ROOT}/cosign.key" ]]; then
        log_warn "Cosign keys already exist, skipping"
        return
    fi

    if ! command -v cosign &> /dev/null; then
        log_warn "cosign not installed, creating placeholder keys"
        touch "${PROJECT_ROOT}/cosign.key"
        touch "${PROJECT_ROOT}/cosign.pub"
        echo "# Placeholder - install cosign and run: cosign generate-key-pair" > "${PROJECT_ROOT}/cosign.key"
        echo "# Placeholder - install cosign and run: cosign generate-key-pair" > "${PROJECT_ROOT}/cosign.pub"
        return
    fi

    log_info "Generating Cosign key pair (you will be prompted for a password)..."
    cd "${PROJECT_ROOT}"

    # Use COSIGN_PASSWORD from env if set, otherwise prompt
    if [[ -n "${COSIGN_PASSWORD:-}" ]]; then
        cosign generate-key-pair
    else
        log_warn "Set COSIGN_PASSWORD environment variable to avoid prompt"
        cosign generate-key-pair
    fi

    log_success "Cosign keys generated"
}

# Check Docker resources
check_docker_resources() {
    log_info "Checking Docker resources..."

    # Try to get Docker info
    local mem_bytes
    mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")

    if [[ "${mem_bytes}" != "0" ]]; then
        local mem_gb=$((mem_bytes / 1024 / 1024 / 1024))
        if [[ ${mem_gb} -lt 4 ]]; then
            log_warn "Docker has ${mem_gb}GB RAM allocated. Recommend at least 4GB for full stack."
        else
            log_success "Docker has ${mem_gb}GB RAM allocated"
        fi
    fi
}

# Set up vm.max_map_count for SonarQube (Linux only)
setup_sysctl() {
    if [[ "$(uname)" == "Linux" ]]; then
        local current_value
        current_value=$(sysctl -n vm.max_map_count 2>/dev/null || echo "0")

        if [[ ${current_value} -lt 262144 ]]; then
            log_warn "vm.max_map_count is ${current_value}, SonarQube needs at least 262144"
            echo ""
            echo "Run this command to fix (requires sudo):"
            echo "  sudo sysctl -w vm.max_map_count=262144"
            echo ""
            echo "To make it permanent, add to /etc/sysctl.conf:"
            echo "  vm.max_map_count=262144"
        fi
    fi
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo " Golden Path Local Environment Setup"
    echo "=========================================="
    echo ""

    cd "${PROJECT_ROOT}"

    check_prerequisites
    echo ""
    check_optional_tools
    echo ""
    check_docker_resources
    echo ""
    setup_sysctl
    echo ""
    setup_env
    echo ""
    setup_cosign_keys
    echo ""

    log_success "Bootstrap complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review .env file and update values if needed"
    echo "  2. Run 'make up' to start the stack"
    echo "  3. Run 'make health' to verify services"
    echo "  4. Run 'make urls' to see service URLs"
    echo ""
}

main "$@"
