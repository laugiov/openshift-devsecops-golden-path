#!/bin/bash
set -euo pipefail

# Validation script for Golden Path local environment
# Run this to verify all components are correctly configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((++PASS)) || true; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((++FAIL)) || true; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((++WARN)) || true; }
info() { echo -e "${CYAN}$1${NC}"; }

echo ""
echo "=========================================="
echo " Golden Path Setup Validation"
echo "=========================================="
echo ""

# Level 1: File structure
info "Level 1: Repository Structure"

[[ -f "${PROJECT_ROOT}/docker-compose.yml" ]] && pass "docker-compose.yml exists" || fail "docker-compose.yml missing"
[[ -f "${PROJECT_ROOT}/Makefile" ]] && pass "Makefile exists" || fail "Makefile missing"
[[ -f "${PROJECT_ROOT}/kind-config.yaml" ]] && pass "kind-config.yaml exists" || fail "kind-config.yaml missing"
[[ -f "${PROJECT_ROOT}/.env.example" ]] && pass ".env.example exists" || fail ".env.example missing"

[[ -d "${PROJECT_ROOT}/demo-service" ]] && pass "demo-service directory exists" || fail "demo-service directory missing"
[[ -f "${PROJECT_ROOT}/demo-service/Dockerfile" ]] && pass "demo-service/Dockerfile exists" || fail "demo-service/Dockerfile missing"
[[ -f "${PROJECT_ROOT}/demo-service/package.json" ]] && pass "demo-service/package.json exists" || fail "demo-service/package.json missing"

[[ -d "${PROJECT_ROOT}/scripts/setup" ]] && pass "scripts/setup exists" || fail "scripts/setup missing"
[[ -d "${PROJECT_ROOT}/scripts/scanners" ]] && pass "scripts/scanners exists" || fail "scripts/scanners missing"
[[ -d "${PROJECT_ROOT}/scripts/signing" ]] && pass "scripts/signing exists" || fail "scripts/signing missing"
[[ -d "${PROJECT_ROOT}/scripts/sbom" ]] && pass "scripts/sbom exists" || fail "scripts/sbom missing"

echo ""

# Level 2: Scripts are executable
info "Level 2: Script Permissions"

for script in "${PROJECT_ROOT}"/scripts/**/*.sh; do
    if [[ -x "$script" ]]; then
        pass "$(basename "$script") is executable"
    else
        warn "$(basename "$script") not executable - run: chmod +x $script"
    fi
done

echo ""

# Level 3: Required tools
info "Level 3: Required Tools"

command -v docker &> /dev/null && pass "docker installed" || fail "docker not installed"
command -v docker compose &> /dev/null && pass "docker compose installed" || fail "docker compose not installed"

echo ""

# Level 4: Optional tools
info "Level 4: Optional Tools (needed for full demo)"

command -v kind &> /dev/null && pass "kind installed" || warn "kind not installed (needed for Level 3)"
command -v kubectl &> /dev/null && pass "kubectl installed" || warn "kubectl not installed (needed for Level 3)"
command -v helm &> /dev/null && pass "helm installed" || warn "helm not installed"
command -v cosign &> /dev/null && pass "cosign installed" || warn "cosign not installed (image signing disabled)"
command -v trivy &> /dev/null && pass "trivy installed" || warn "trivy not installed (will use Docker)"
command -v semgrep &> /dev/null && pass "semgrep installed" || warn "semgrep not installed (will use Docker)"
command -v jq &> /dev/null && pass "jq installed" || warn "jq not installed (report parsing limited)"

echo ""

# Level 5: Docker resources
info "Level 5: Docker Resources"

if docker info &> /dev/null; then
    pass "Docker daemon running"

    mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    if [[ "${mem_bytes}" != "0" ]]; then
        mem_gb=$((mem_bytes / 1024 / 1024 / 1024))
        if [[ ${mem_gb} -ge 4 ]]; then
            pass "Docker has ${mem_gb}GB RAM (>=4GB recommended)"
        else
            warn "Docker has ${mem_gb}GB RAM (4GB+ recommended for full stack)"
        fi
    fi
else
    fail "Docker daemon not running"
fi

echo ""

# Level 6: Services (if running)
info "Level 6: Running Services (if started)"

if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null | grep -q "200"; then
    pass "Jenkins responding on :8080"
else
    warn "Jenkins not responding (run 'make up' first)"
fi

if curl -s http://localhost:9000/api/system/status 2>/dev/null | grep -q "UP"; then
    pass "SonarQube responding on :9000"
else
    warn "SonarQube not responding (run 'make up' first)"
fi

if curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ 2>/dev/null | grep -qE "200|302"; then
    pass "Nexus responding on :8081"
else
    warn "Nexus not responding (run 'make up' first)"
fi

if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/v2/ 2>/dev/null | grep -q "200"; then
    pass "Registry responding on :5000"
else
    warn "Registry not responding (run 'make up' first)"
fi

echo ""

# Summary
echo "=========================================="
echo " Summary"
echo "=========================================="
echo ""
echo -e "  ${GREEN}Passed:${NC}   ${PASS}"
echo -e "  ${RED}Failed:${NC}   ${FAIL}"
echo -e "  ${YELLOW}Warnings:${NC} ${WARN}"
echo ""

if [[ ${FAIL} -eq 0 ]]; then
    if [[ ${WARN} -eq 0 ]]; then
        echo -e "${GREEN}All checks passed! Environment is fully configured.${NC}"
    else
        echo -e "${YELLOW}Environment is configured with some optional components missing.${NC}"
        echo "Run 'make bootstrap' for full setup instructions."
    fi
    exit 0
else
    echo -e "${RED}Some required components are missing. Please fix failures above.${NC}"
    exit 1
fi
