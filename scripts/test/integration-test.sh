#!/bin/bash
# Integration Tests for Golden Path DevSecOps Stack
#
# This script starts Docker services, validates they are healthy,
# runs integration tests, and reports results.
#
# Usage:
#   ./integration-test.sh [--quick] [--keep]
#
# Options:
#   --quick  Skip slow tests (SonarQube analysis)
#   --keep   Keep services running after tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test configuration
QUICK_MODE=false
KEEP_SERVICES=false
TESTS_PASSED=0
TESTS_FAILED=0
TIMEOUT=120

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick) QUICK_MODE=true; shift ;;
        --keep) KEEP_SERVICES=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Cleanup function
cleanup() {
    if [[ "$KEEP_SERVICES" == "false" ]]; then
        log_info "Stopping services..."
        cd "$PROJECT_ROOT" && docker compose down -v 2>/dev/null || true
    else
        log_info "Keeping services running (--keep specified)"
    fi
}

# Wait for service to be healthy
wait_for_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    local waited=0

    log_info "Waiting for $name to be ready..."
    while [[ $waited -lt $TIMEOUT ]]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [[ "$code" == "$expected_code" ]]; then
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    return 1
}

# Test: Service health checks
test_service_health() {
    log_info "Testing service health endpoints..."

    # Registry
    if curl -sf http://localhost:5000/v2/ >/dev/null 2>&1; then
        log_pass "Registry is healthy"
    else
        log_fail "Registry is not responding"
    fi

    # SonarQube
    if curl -sf http://localhost:9000/api/system/status 2>&1 | grep -q '"status":"UP"'; then
        log_pass "SonarQube is healthy"
    else
        log_fail "SonarQube is not healthy"
    fi

    # Nexus
    if curl -sf http://localhost:8081/service/rest/v1/status 2>&1 | grep -q "STARTED"; then
        log_pass "Nexus is healthy"
    else
        log_fail "Nexus is not responding correctly"
    fi

    # Jenkins
    local jenkins_code
    jenkins_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null || echo "000")
    if [[ "$jenkins_code" == "200" ]]; then
        log_pass "Jenkins is healthy"
    else
        log_fail "Jenkins is not responding (code: $jenkins_code)"
    fi
}

# Test: Docker build works
test_docker_build() {
    log_info "Testing Docker build..."

    cd "$PROJECT_ROOT/demo-service"
    if docker build -t demo-service:test . >/dev/null 2>&1; then
        log_pass "Docker build succeeded"
    else
        log_fail "Docker build failed"
        return
    fi

    # Test the built image runs
    local container_id
    container_id=$(docker run -d -p 3001:3000 demo-service:test)
    sleep 3

    if curl -sf http://localhost:3001/health 2>&1 | grep -q "healthy"; then
        log_pass "Built container responds to health check"
    else
        log_fail "Built container health check failed"
    fi

    docker stop "$container_id" >/dev/null 2>&1
    docker rm "$container_id" >/dev/null 2>&1
}

# Test: Push to registry
test_registry_push() {
    log_info "Testing push to local registry..."

    docker tag demo-service:test localhost:5000/demo-service:test 2>/dev/null || true
    if docker push localhost:5000/demo-service:test >/dev/null 2>&1; then
        log_pass "Image pushed to registry"
    else
        log_fail "Failed to push image to registry"
        return
    fi

    # Verify image exists in registry
    if curl -sf http://localhost:5000/v2/demo-service/tags/list 2>&1 | grep -q "test"; then
        log_pass "Image verified in registry"
    else
        log_fail "Image not found in registry"
    fi
}

# Test: SBOM generation
test_sbom_generation() {
    log_info "Testing SBOM generation..."

    if command -v syft &>/dev/null; then
        if syft localhost:5000/demo-service:test -o cyclonedx-json > /tmp/sbom-test.json 2>/dev/null; then
            if jq -e '.components | length > 0' /tmp/sbom-test.json >/dev/null 2>&1; then
                log_pass "SBOM generated with components"
            else
                log_fail "SBOM has no components"
            fi
        else
            log_fail "SBOM generation failed"
        fi
        rm -f /tmp/sbom-test.json
    else
        log_skip "Syft not installed - skipping SBOM test"
    fi
}

# Test: Security scan
test_security_scan() {
    log_info "Testing security scan..."

    if command -v trivy &>/dev/null; then
        if trivy image --severity HIGH,CRITICAL --exit-code 0 localhost:5000/demo-service:test >/dev/null 2>&1; then
            log_pass "Trivy scan completed"
        else
            log_fail "Trivy scan failed"
        fi
    else
        log_skip "Trivy not installed - skipping security scan"
    fi
}

# Test: SonarQube analysis (slow)
test_sonarqube_analysis() {
    if [[ "$QUICK_MODE" == "true" ]]; then
        log_skip "SonarQube analysis (--quick mode)"
        return
    fi

    log_info "Testing SonarQube analysis..."

    cd "$PROJECT_ROOT/demo-service"
    if command -v sonar-scanner &>/dev/null; then
        if sonar-scanner \
            -Dsonar.projectKey=demo-service-test \
            -Dsonar.sources=src \
            -Dsonar.host.url=http://localhost:9000 \
            -Dsonar.token=admin >/dev/null 2>&1; then
            log_pass "SonarQube analysis completed"
        else
            log_fail "SonarQube analysis failed"
        fi
    else
        log_skip "sonar-scanner not installed"
    fi
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║       Golden Path Integration Tests                              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    trap cleanup EXIT

    # Start services
    log_info "Starting Docker services..."
    cd "$PROJECT_ROOT"

    if ! docker compose up -d 2>&1 | tail -5; then
        log_fail "Failed to start Docker services"
        exit 1
    fi

    # Wait for services
    log_info "Waiting for services to initialize (this may take 2-3 minutes)..."
    sleep 30

    if ! wait_for_service "Registry" "http://localhost:5000/v2/"; then
        log_fail "Registry failed to start"
    fi

    if ! wait_for_service "Jenkins" "http://localhost:8080/login"; then
        log_fail "Jenkins failed to start"
    fi

    if ! wait_for_service "SonarQube" "http://localhost:9000/api/system/status"; then
        log_fail "SonarQube failed to start"
    fi

    echo ""
    log_info "Running integration tests..."
    echo ""

    # Run tests
    test_service_health
    test_docker_build
    test_registry_push
    test_sbom_generation
    test_security_scan
    test_sonarqube_analysis

    # Summary
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    Integration Test Results                      ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  ${GREEN}Passed: %-4s${NC}  ${RED}Failed: %-4s${NC}                                     ║\n" "$TESTS_PASSED" "$TESTS_FAILED"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
