#!/bin/bash
set -euo pipefail

# Wait for services to be healthy

TIMEOUT=${1:-300}  # Default 5 minutes
INTERVAL=5

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_waiting() { echo -e "${YELLOW}[WAIT]${NC} $1"; }

check_service() {
    local name=$1
    local url=$2
    local check_cmd=$3

    if eval "${check_cmd}" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

wait_for_service() {
    local name=$1
    local url=$2
    local check_cmd=$3
    local elapsed=0

    log_waiting "Waiting for ${name}..."

    while [[ ${elapsed} -lt ${TIMEOUT} ]]; do
        if check_service "${name}" "${url}" "${check_cmd}"; then
            log_success "${name} is ready"
            return 0
        fi
        sleep ${INTERVAL}
        elapsed=$((elapsed + INTERVAL))
        echo -n "."
    done

    echo ""
    log_error "${name} did not become ready within ${TIMEOUT}s"
    return 1
}

main() {
    echo ""
    echo "Waiting for services to be ready (timeout: ${TIMEOUT}s)..."
    echo ""

    local failed=0

    # Jenkins
    wait_for_service "Jenkins" "http://localhost:8080" \
        "curl -sf http://localhost:8080/login" || failed=1

    # SonarQube
    wait_for_service "SonarQube" "http://localhost:9000" \
        "curl -sf http://localhost:9000/api/system/status | grep -q UP" || failed=1

    # Nexus
    wait_for_service "Nexus" "http://localhost:8081" \
        "curl -sf http://localhost:8081/service/rest/v1/status" || failed=1

    # Registry
    wait_for_service "Registry" "http://localhost:5000" \
        "curl -sf http://localhost:5000/v2/" || failed=1

    echo ""

    if [[ ${failed} -eq 0 ]]; then
        log_success "All services are ready!"
        return 0
    else
        log_error "Some services failed to start"
        return 1
    fi
}

main "$@"
