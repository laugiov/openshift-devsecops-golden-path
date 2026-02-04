#!/bin/bash
set -euo pipefail

# Secrets Detection Scanner
# Scans for accidentally committed secrets

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
SECRETS_ADAPTER=${SECRETS_ADAPTER:-gitleaks}
TARGET_PATH=${1:-${PROJECT_ROOT}}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/reports}
FAIL_ON_FINDINGS=${FAIL_ON_FINDINGS:-true}

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

run_gitleaks() {
    log_info "Running Gitleaks secrets scan..."

    local output_file="${OUTPUT_DIR}/secrets-gitleaks.json"
    local exit_code=0

    # Check for config file
    local config_args=""
    if [[ -f "${TARGET_PATH}/.gitleaks.toml" ]]; then
        config_args="--config ${TARGET_PATH}/.gitleaks.toml"
    fi

    if command -v gitleaks &> /dev/null; then
        gitleaks detect \
            --source "${TARGET_PATH}" \
            --report-format json \
            --report-path "${output_file}" \
            --no-git \
            ${config_args} \
            || exit_code=$?
    else
        log_info "Using Docker for Gitleaks..."
        local docker_config_args=""
        if [[ -f "${TARGET_PATH}/.gitleaks.toml" ]]; then
            docker_config_args="--config /source/.gitleaks.toml"
        fi
        docker run --rm \
            -v "${TARGET_PATH}:/source:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            zricethezav/gitleaks:latest \
            detect \
                --source /source \
                --report-format json \
                --report-path /reports/secrets-gitleaks.json \
                --no-git \
                ${docker_config_args} \
            || exit_code=$?
    fi

    # Exit code 1 means findings, other codes are errors
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "No secrets found"
        return 0
    elif [[ ${exit_code} -eq 1 ]]; then
        if [[ -f "${output_file}" ]]; then
            local count
            count=$(jq 'length' "${output_file}" 2>/dev/null || echo "unknown")
            log_error "Found ${count} potential secrets!"
            echo ""
            echo "Review: ${output_file}"

            if [[ "${FAIL_ON_FINDINGS}" == "true" ]]; then
                return 1
            fi
        fi
    else
        log_error "Scanner error (exit code: ${exit_code})"
        return ${exit_code}
    fi
}

run_trufflehog() {
    log_info "Running TruffleHog secrets scan..."

    local output_file="${OUTPUT_DIR}/secrets-trufflehog.json"

    if command -v trufflehog &> /dev/null; then
        trufflehog filesystem "${TARGET_PATH}" \
            --json \
            > "${output_file}" 2>&1 || true
    else
        log_info "Using Docker for TruffleHog..."
        docker run --rm \
            -v "${TARGET_PATH}:/source:ro" \
            trufflesecurity/trufflehog:latest \
            filesystem /source \
                --json \
            > "${output_file}" 2>&1 || true
    fi

    if [[ -s "${output_file}" ]]; then
        local count
        count=$(wc -l < "${output_file}" | tr -d ' ')
        if [[ ${count} -gt 0 ]]; then
            log_error "Found ${count} potential secrets!"
            if [[ "${FAIL_ON_FINDINGS}" == "true" ]]; then
                return 1
            fi
        fi
    else
        log_success "No secrets found"
    fi
}

main() {
    log_info "Secrets Scanner"
    log_info "Adapter: ${SECRETS_ADAPTER}"
    log_info "Target:  ${TARGET_PATH}"
    echo ""

    case "${SECRETS_ADAPTER}" in
        gitleaks)
            run_gitleaks
            ;;
        trufflehog)
            run_trufflehog
            ;;
        *)
            log_error "Unknown adapter: ${SECRETS_ADAPTER}"
            echo "Available adapters: gitleaks, trufflehog"
            exit 1
            ;;
    esac
}

main "$@"
