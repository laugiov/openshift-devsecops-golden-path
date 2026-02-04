#!/bin/bash
set -euo pipefail

# SCA Scanner Wrapper (Software Composition Analysis)
# Scans dependencies for known vulnerabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
SCA_ADAPTER=${SCA_ADAPTER:-trivy}
TARGET_PATH=${1:-${PROJECT_ROOT}/demo-service}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/reports}
FAIL_ON_CRITICAL=${FAIL_ON_CRITICAL:-true}
FAIL_ON_HIGH=${FAIL_ON_HIGH:-false}
SEVERITY_THRESHOLD=${SEVERITY_THRESHOLD:-CRITICAL,HIGH}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

mkdir -p "${OUTPUT_DIR}"

run_trivy() {
    log_info "Running Trivy SCA scan..."

    local output_file="${OUTPUT_DIR}/sca-trivy.json"
    local exit_code=0

    if command -v trivy &> /dev/null; then
        # Use local trivy
        trivy fs \
            --severity "${SEVERITY_THRESHOLD}" \
            --format json \
            --output "${output_file}" \
            "${TARGET_PATH}" || exit_code=$?
    else
        # Use Docker
        log_info "Using Docker for Trivy..."
        docker run --rm \
            -v "${TARGET_PATH}:/target:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            aquasec/trivy:latest \
            fs \
                --severity "${SEVERITY_THRESHOLD}" \
                --format json \
                --output /reports/sca-trivy.json \
                /target || exit_code=$?
    fi

    # Parse results
    if [[ -f "${output_file}" ]]; then
        local critical
        local high
        local medium

        critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "${output_file}" 2>/dev/null || echo "0")
        high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "${output_file}" 2>/dev/null || echo "0")
        medium=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "${output_file}" 2>/dev/null || echo "0")

        echo ""
        echo "SCA Results:"
        echo "  Critical: ${critical}"
        echo "  High:     ${high}"
        echo "  Medium:   ${medium}"
        echo ""
        echo "Report: ${output_file}"

        if [[ "${FAIL_ON_CRITICAL}" == "true" ]] && [[ ${critical} -gt 0 ]]; then
            log_error "Found ${critical} critical vulnerabilities"
            return 1
        fi

        if [[ "${FAIL_ON_HIGH}" == "true" ]] && [[ ${high} -gt 0 ]]; then
            log_error "Found ${high} high vulnerabilities"
            return 1
        fi
    fi

    log_success "SCA scan completed"
    return 0
}

run_grype() {
    log_info "Running Grype SCA scan..."

    local output_file="${OUTPUT_DIR}/sca-grype.json"

    if command -v grype &> /dev/null; then
        grype dir:"${TARGET_PATH}" \
            --output json \
            --file "${output_file}" || true
    else
        log_info "Using Docker for Grype..."
        docker run --rm \
            -v "${TARGET_PATH}:/target:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            anchore/grype:latest \
            dir:/target \
                --output json \
                --file /reports/sca-grype.json || true
    fi

    log_success "SCA scan completed"
}

main() {
    log_info "SCA Scanner"
    log_info "Adapter: ${SCA_ADAPTER}"
    log_info "Target:  ${TARGET_PATH}"
    echo ""

    case "${SCA_ADAPTER}" in
        trivy)
            run_trivy
            ;;
        grype)
            run_grype
            ;;
        *)
            log_error "Unknown adapter: ${SCA_ADAPTER}"
            echo "Available adapters: trivy, grype"
            exit 1
            ;;
    esac
}

main "$@"
