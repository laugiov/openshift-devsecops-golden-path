#!/bin/bash
set -euo pipefail

# SAST Scanner Wrapper
# Supports multiple backends via adapters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
SAST_ADAPTER=${SAST_ADAPTER:-semgrep}
TARGET_PATH=${1:-${PROJECT_ROOT}/demo-service/src}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/reports}
FAIL_ON_HIGH=${FAIL_ON_HIGH:-true}

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

run_semgrep() {
    log_info "Running Semgrep SAST scan..."

    local output_file="${OUTPUT_DIR}/sast-semgrep.json"

    if command -v semgrep &> /dev/null; then
        # Use local semgrep
        semgrep scan \
            --config auto \
            --json \
            --output "${output_file}" \
            "${TARGET_PATH}" || true
    else
        # Use Docker
        log_info "Using Docker for Semgrep..."
        docker run --rm \
            -v "${TARGET_PATH}:/src:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            returntocorp/semgrep:latest \
            semgrep scan \
                --config auto \
                --json \
                --output /reports/sast-semgrep.json \
                /src || true
    fi

    # Parse results
    if [[ -f "${output_file}" ]]; then
        local total
        local high
        local medium

        total=$(jq '.results | length' "${output_file}" 2>/dev/null || echo "0")
        high=$(jq '[.results[] | select(.extra.severity == "ERROR" or .extra.severity == "HIGH")] | length' "${output_file}" 2>/dev/null || echo "0")
        medium=$(jq '[.results[] | select(.extra.severity == "WARNING" or .extra.severity == "MEDIUM")] | length' "${output_file}" 2>/dev/null || echo "0")

        echo ""
        echo "SAST Results:"
        echo "  Total findings: ${total}"
        echo "  High/Critical:  ${high}"
        echo "  Medium:         ${medium}"
        echo ""
        echo "Report: ${output_file}"

        if [[ "${FAIL_ON_HIGH}" == "true" ]] && [[ ${high} -gt 0 ]]; then
            log_error "Found ${high} high/critical severity findings"
            return 1
        fi
    else
        log_warn "No output file generated"
    fi

    log_success "SAST scan completed"
    return 0
}

run_fortify() {
    log_info "Running Fortify SAST scan (adapter)..."
    source "${SCRIPT_DIR}/adapters/fortify-adapter.sh"
    fortify_scan "${TARGET_PATH}" "${OUTPUT_DIR}"
}

run_checkmarx() {
    log_info "Running Checkmarx SAST scan (adapter)..."
    source "${SCRIPT_DIR}/adapters/checkmarx-adapter.sh"
    checkmarx_scan "${TARGET_PATH}" "${OUTPUT_DIR}"
}

main() {
    log_info "SAST Scanner"
    log_info "Adapter: ${SAST_ADAPTER}"
    log_info "Target:  ${TARGET_PATH}"
    echo ""

    case "${SAST_ADAPTER}" in
        semgrep)
            run_semgrep
            ;;
        fortify)
            run_fortify
            ;;
        checkmarx)
            run_checkmarx
            ;;
        *)
            log_error "Unknown adapter: ${SAST_ADAPTER}"
            echo "Available adapters: semgrep, fortify, checkmarx"
            exit 1
            ;;
    esac
}

main "$@"
