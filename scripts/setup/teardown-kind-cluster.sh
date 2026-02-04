#!/bin/bash
set -euo pipefail

# Tear down Kind cluster

CLUSTER_NAME=${CLUSTER_NAME:-golden-path}

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    log_info "Deleting Kind cluster: ${CLUSTER_NAME}..."

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "${CLUSTER_NAME}"
        log_success "Cluster deleted"
    else
        log_info "Cluster '${CLUSTER_NAME}' does not exist"
    fi

    # Disconnect registry from kind network if connected
    if docker network inspect kind &>/dev/null; then
        docker network disconnect kind golden-path-registry 2>/dev/null || true
    fi

    log_success "Teardown complete"
}

main "$@"
