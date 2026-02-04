#!/bin/bash
set -euo pipefail

# Generate Cosign signing keys for image signing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    cd "${PROJECT_ROOT}"

    if ! command -v cosign &> /dev/null; then
        log_error "cosign is not installed"
        echo ""
        echo "Install cosign:"
        echo "  macOS:  brew install cosign"
        echo "  Linux:  See https://docs.sigstore.dev/cosign/installation/"
        exit 1
    fi

    if [[ -f "cosign.key" ]]; then
        log_warn "Cosign keys already exist"
        read -p "Overwrite existing keys? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing keys"
            exit 0
        fi
        rm -f cosign.key cosign.pub
    fi

    log_info "Generating Cosign key pair..."
    echo ""

    # If COSIGN_PASSWORD is set, use it
    if [[ -n "${COSIGN_PASSWORD:-}" ]]; then
        log_info "Using COSIGN_PASSWORD from environment"
        cosign generate-key-pair
    else
        log_warn "COSIGN_PASSWORD not set - you will be prompted"
        echo "Hint: Set COSIGN_PASSWORD=<password> in your .env file"
        echo ""
        cosign generate-key-pair
    fi

    if [[ -f "cosign.key" ]] && [[ -f "cosign.pub" ]]; then
        log_success "Keys generated successfully"
        echo ""
        echo "Files created:"
        echo "  - cosign.key (private key - keep secret!)"
        echo "  - cosign.pub (public key - distribute freely)"
        echo ""
        echo "Add to .gitignore (already done):"
        echo "  cosign.key"
        echo ""
        echo "Usage:"
        echo "  Sign:   cosign sign --key cosign.key <image>"
        echo "  Verify: cosign verify --key cosign.pub <image>"
    else
        log_error "Key generation failed"
        exit 1
    fi
}

main "$@"
