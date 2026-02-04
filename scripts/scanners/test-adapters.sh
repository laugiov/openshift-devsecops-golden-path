#!/bin/bash
# Test script for enterprise scanner adapters
#
# This script validates that the Fortify and Checkmarx adapters:
# 1. Generate valid SARIF output in mock mode
# 2. Parse reports correctly
# 3. Make correct gate decisions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_OUTPUT_DIR="${PROJECT_ROOT}/test-output/adapters"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Check if jq is available
check_dependencies() {
    log_test "Checking dependencies..."
    if command -v jq &> /dev/null; then
        log_pass "jq is available"
    else
        log_fail "jq is not installed"
        echo "Install jq to run these tests: apt-get install jq"
        exit 1
    fi
}

# Test Fortify adapter mock mode
test_fortify_mock() {
    log_test "Testing Fortify adapter (mock mode)..."

    local output_dir="${TEST_OUTPUT_DIR}/fortify"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    # Run adapter in mock mode
    FORTIFY_MOCK_MODE=true \
    FORTIFY_PROJECT="test-project" \
    FAIL_ON_HIGH=false \
        bash "${SCRIPT_DIR}/adapters/fortify-adapter.sh" "${PROJECT_ROOT}" "$output_dir"

    local exit_code=$?

    # Check exit code (should pass with FAIL_ON_HIGH=false)
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Fortify adapter completed successfully"
    else
        log_fail "Fortify adapter failed with exit code $exit_code"
    fi

    # Check SARIF output exists
    if [[ -f "${output_dir}/sast-fortify.sarif.json" ]]; then
        log_pass "SARIF report generated"
    else
        log_fail "SARIF report not found"
        return 1
    fi

    # Validate SARIF structure
    if jq -e '.runs[0].tool.driver.name' "${output_dir}/sast-fortify.sarif.json" > /dev/null 2>&1; then
        log_pass "SARIF structure is valid"
    else
        log_fail "Invalid SARIF structure"
    fi

    # Check summary file
    if [[ -f "${output_dir}/fortify-summary.json" ]]; then
        log_pass "Summary report generated"

        # Validate summary content
        local total
        total=$(jq -r '.findings.total' "${output_dir}/fortify-summary.json")
        if [[ "$total" =~ ^[0-9]+$ ]]; then
            log_pass "Summary contains valid findings count: $total"
        else
            log_fail "Invalid findings count in summary"
        fi
    else
        log_fail "Summary report not found"
    fi
}

# Test Checkmarx adapter mock mode
test_checkmarx_mock() {
    log_test "Testing Checkmarx adapter (mock mode)..."

    local output_dir="${TEST_OUTPUT_DIR}/checkmarx"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    # Run adapter in mock mode
    CX_MOCK_MODE=true \
    CX_PROJECT="test-project" \
    FAIL_ON_HIGH=false \
        bash "${SCRIPT_DIR}/adapters/checkmarx-adapter.sh" "${PROJECT_ROOT}" "$output_dir"

    local exit_code=$?

    # Check exit code (should pass with FAIL_ON_HIGH=false)
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Checkmarx adapter completed successfully"
    else
        log_fail "Checkmarx adapter failed with exit code $exit_code"
    fi

    # Check SARIF output exists
    if [[ -f "${output_dir}/sast-checkmarx.sarif.json" ]]; then
        log_pass "SARIF report generated"
    else
        log_fail "SARIF report not found"
        return 1
    fi

    # Validate SARIF structure
    if jq -e '.runs[0].tool.driver.name' "${output_dir}/sast-checkmarx.sarif.json" > /dev/null 2>&1; then
        log_pass "SARIF structure is valid"
    else
        log_fail "Invalid SARIF structure"
    fi

    # Check summary file
    if [[ -f "${output_dir}/checkmarx-summary.json" ]]; then
        log_pass "Summary report generated"
    else
        log_fail "Summary report not found"
    fi
}

# Test gate decision with High findings
test_gate_high_fail() {
    log_test "Testing gate decision (fail on High)..."

    local output_dir="${TEST_OUTPUT_DIR}/gate-test"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    # Run with FAIL_ON_HIGH=true (should fail because mock has High findings)
    local exit_code=0
    FORTIFY_MOCK_MODE=true \
    FAIL_ON_CRITICAL=true \
    FAIL_ON_HIGH=true \
        bash "${SCRIPT_DIR}/adapters/fortify-adapter.sh" "${PROJECT_ROOT}" "$output_dir" || exit_code=$?

    # Should fail because mock report has High findings
    if [[ $exit_code -ne 0 ]]; then
        log_pass "Gate correctly fails on High findings"
    else
        log_fail "Gate should have failed on High findings"
    fi
}

# Test gate decision with threshold relaxed
test_gate_high_pass() {
    log_test "Testing gate decision (ignore High)..."

    local output_dir="${TEST_OUTPUT_DIR}/gate-pass"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    # Run with FAIL_ON_HIGH=false (should pass)
    FORTIFY_MOCK_MODE=true \
    FAIL_ON_CRITICAL=true \
    FAIL_ON_HIGH=false \
        bash "${SCRIPT_DIR}/adapters/fortify-adapter.sh" "${PROJECT_ROOT}" "$output_dir"

    local exit_code=$?

    # Should pass because we ignore High
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Gate correctly passes when High threshold is relaxed"
    else
        log_fail "Gate should have passed with FAIL_ON_HIGH=false"
    fi
}

# Test parsing sample reports
test_sample_reports() {
    log_test "Testing sample report parsing..."

    local samples_dir="${PROJECT_ROOT}/samples"

    # Test Fortify sample
    if [[ -f "${samples_dir}/fortify-report.sarif.json" ]]; then
        local fortify_total
        fortify_total=$(jq '[.runs[].results[]] | length' "${samples_dir}/fortify-report.sarif.json")
        if [[ "$fortify_total" -gt 0 ]]; then
            log_pass "Fortify sample report parsed: $fortify_total findings"
        else
            log_fail "Failed to parse Fortify sample report"
        fi
    else
        log_fail "Fortify sample report not found"
    fi

    # Test Checkmarx sample
    if [[ -f "${samples_dir}/checkmarx-report.sarif.json" ]]; then
        local cx_total
        cx_total=$(jq '[.runs[].results[]] | length' "${samples_dir}/checkmarx-report.sarif.json")
        if [[ "$cx_total" -gt 0 ]]; then
            log_pass "Checkmarx sample report parsed: $cx_total findings"
        else
            log_fail "Failed to parse Checkmarx sample report"
        fi
    else
        log_fail "Checkmarx sample report not found"
    fi
}

# Cleanup
cleanup() {
    log_test "Cleaning up test output..."
    rm -rf "${TEST_OUTPUT_DIR}"
    log_pass "Cleanup complete"
}

# Main
main() {
    echo ""
    echo "=============================================="
    echo "  Enterprise Scanner Adapter Tests"
    echo "=============================================="
    echo ""

    check_dependencies

    echo ""
    test_fortify_mock

    echo ""
    test_checkmarx_mock

    echo ""
    test_gate_high_fail

    echo ""
    test_gate_high_pass

    echo ""
    test_sample_reports

    echo ""
    cleanup

    echo ""
    echo "=============================================="
    echo "  Test Results"
    echo "=============================================="
    echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
    echo "=============================================="
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
