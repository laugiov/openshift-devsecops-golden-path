#!/bin/bash
set -euo pipefail

# SBOM Generator
# Generates CycloneDX Software Bill of Materials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
# Convert relative path to absolute if needed
_TARGET=${1:-demo-service}
if [[ "${_TARGET}" = /* ]]; then
    TARGET_PATH="${_TARGET}"
else
    TARGET_PATH="${PROJECT_ROOT}/${_TARGET}"
fi
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_ROOT}/reports}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-json}

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

mkdir -p "${OUTPUT_DIR}"

generate_with_trivy() {
    log_info "Generating SBOM with Trivy..."

    local output_file="${OUTPUT_DIR}/sbom-cyclonedx.json"

    if command -v trivy &> /dev/null; then
        trivy fs \
            --format cyclonedx \
            --output "${output_file}" \
            "${TARGET_PATH}"
    else
        log_info "Using Docker for Trivy..."
        docker run --rm \
            -v "${TARGET_PATH}:/target:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            aquasec/trivy:latest \
            fs \
                --format cyclonedx \
                --output /reports/sbom-cyclonedx.json \
                /target
    fi

    if [[ -f "${output_file}" ]]; then
        local component_count
        component_count=$(jq '.components | length' "${output_file}" 2>/dev/null || echo "0")

        log_success "SBOM generated"
        echo ""
        echo "Output: ${output_file}"
        echo "Components: ${component_count}"
        echo "Format: CycloneDX JSON"
    else
        log_error "SBOM generation failed"
        return 1
    fi
}

generate_with_syft() {
    log_info "Generating SBOM with Syft..."

    local output_file="${OUTPUT_DIR}/sbom-cyclonedx.json"

    if command -v syft &> /dev/null; then
        syft "${TARGET_PATH}" \
            --output cyclonedx-json="${output_file}"
    else
        log_info "Using Docker for Syft..."
        docker run --rm \
            -v "${TARGET_PATH}:/target:ro" \
            -v "${OUTPUT_DIR}:/reports" \
            anchore/syft:latest \
            /target \
                --output cyclonedx-json=/reports/sbom-cyclonedx.json
    fi

    if [[ -f "${output_file}" ]]; then
        log_success "SBOM generated: ${output_file}"
    else
        log_error "SBOM generation failed"
        return 1
    fi
}

main() {
    log_info "SBOM Generator"
    log_info "Target: ${TARGET_PATH}"
    log_info "Format: CycloneDX"
    echo ""

    # Prefer Trivy as it's already used for SCA
    generate_with_trivy
}

main "$@"
