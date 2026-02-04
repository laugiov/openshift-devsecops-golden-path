#!/bin/bash
set -euo pipefail

# Sign a container image with Cosign

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE=${1:-}
KEY_FILE="${PROJECT_ROOT}/cosign.key"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 <image>"
    echo ""
    echo "Sign a container image with Cosign"
    echo ""
    echo "Arguments:"
    echo "  image    Full image reference (e.g., localhost:5000/demo-service:v1.0.0)"
    echo ""
    echo "Environment:"
    echo "  COSIGN_PASSWORD  Password for the signing key"
    echo ""
    echo "Examples:"
    echo "  $0 localhost:5000/demo-service:v1.0.0"
    echo "  COSIGN_PASSWORD=secret $0 registry.example.com/app:latest"
}

main() {
    if [[ -z "${IMAGE}" ]]; then
        log_error "Image argument required"
        echo ""
        usage
        exit 1
    fi

    if ! command -v cosign &> /dev/null; then
        log_error "cosign is not installed"
        exit 1
    fi

    if [[ ! -f "${KEY_FILE}" ]]; then
        log_error "Signing key not found: ${KEY_FILE}"
        echo "Run: ./scripts/signing/generate-cosign-keys.sh"
        exit 1
    fi

    # Check if key file is a placeholder
    if grep -q "Placeholder" "${KEY_FILE}" 2>/dev/null; then
        log_error "Signing key is a placeholder. Generate real keys first."
        echo "Run: ./scripts/signing/generate-cosign-keys.sh"
        exit 1
    fi

    log_info "Signing image: ${IMAGE}"

    # Sign the image
    if [[ -n "${COSIGN_PASSWORD:-}" ]]; then
        cosign sign --key "${KEY_FILE}" "${IMAGE}" --yes
    else
        log_warn "COSIGN_PASSWORD not set - you will be prompted"
        cosign sign --key "${KEY_FILE}" "${IMAGE}" --yes
    fi

    log_success "Image signed successfully"

    # Show signature info
    log_info "Verifying signature..."
    cosign verify --key "${PROJECT_ROOT}/cosign.pub" "${IMAGE}" 2>/dev/null || true

    echo ""
    log_success "Done"
}

main "$@"
