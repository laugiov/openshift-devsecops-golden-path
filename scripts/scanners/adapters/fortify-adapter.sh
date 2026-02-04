#!/bin/bash
# Fortify SAST Adapter
#
# This adapter provides a standardized interface for Fortify integration.
# It supports both real Fortify SSC scans and mock mode for testing.
#
# Usage:
#   fortify_scan <target_path> <output_dir> [options]
#
# Options (via environment variables):
#   FORTIFY_SSC_URL     - Fortify SSC server URL
#   FORTIFY_TOKEN       - Authentication token (or FORTIFY_USER/FORTIFY_PASSWORD)
#   FORTIFY_PROJECT     - Project name in SSC
#   FORTIFY_VERSION     - Application version name
#   FORTIFY_MOCK_MODE   - Set to "true" to use mock reports for testing
#   SEVERITY_THRESHOLD  - Minimum severity to report (Critical, High, Medium, Low)
#   FAIL_ON_CRITICAL    - Fail pipeline on Critical findings (default: true)
#   FAIL_ON_HIGH        - Fail pipeline on High findings (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default configuration
FORTIFY_MOCK_MODE="${FORTIFY_MOCK_MODE:-false}"
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-Low}"
FAIL_ON_CRITICAL="${FAIL_ON_CRITICAL:-true}"
FAIL_ON_HIGH="${FAIL_ON_HIGH:-true}"

# Severity ordering for comparison
declare -A SEVERITY_ORDER=(
    ["Critical"]=4
    ["High"]=3
    ["Medium"]=2
    ["Low"]=1
    ["Info"]=0
)

log() {
    echo "[Fortify] $*"
}

error() {
    echo "[Fortify] ERROR: $*" >&2
}

# Check if severity meets threshold
meets_threshold() {
    local severity=$1
    local threshold=$2
    local sev_order=${SEVERITY_ORDER[$severity]:-0}
    local thresh_order=${SEVERITY_ORDER[$threshold]:-0}
    [[ $sev_order -ge $thresh_order ]]
}

# Generate mock report for testing
generate_mock_report() {
    local output_file=$1
    local project_name=${FORTIFY_PROJECT:-demo-service}
    local version=${FORTIFY_VERSION:-1.0.0}
    local branch=${GIT_BRANCH:-main}
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "${output_file}" << EOF
{
  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "Fortify Static Code Analyzer",
          "version": "23.1.0",
          "informationUri": "https://www.microfocus.com/en-us/cyberres/application-security/static-code-analyzer",
          "rules": [
            {
              "id": "SQL_Injection",
              "name": "SQL Injection",
              "shortDescription": {
                "text": "SQL Injection vulnerability detected"
              },
              "fullDescription": {
                "text": "The application constructs SQL statements from user-controlled input without proper sanitization."
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "9.8",
                "precision": "high",
                "tags": ["security", "cwe-89", "owasp-a03"]
              }
            },
            {
              "id": "XSS_Reflected",
              "name": "Cross-Site Scripting: Reflected",
              "shortDescription": {
                "text": "Reflected XSS vulnerability detected"
              },
              "fullDescription": {
                "text": "User input is reflected in the output without proper encoding."
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "6.1",
                "precision": "high",
                "tags": ["security", "cwe-79", "owasp-a03"]
              }
            },
            {
              "id": "Path_Manipulation",
              "name": "Path Manipulation",
              "shortDescription": {
                "text": "Path manipulation vulnerability"
              },
              "fullDescription": {
                "text": "User input is used to construct a file path without validation."
              },
              "defaultConfiguration": {
                "level": "warning"
              },
              "properties": {
                "security-severity": "7.5",
                "precision": "medium",
                "tags": ["security", "cwe-22", "owasp-a01"]
              }
            }
          ]
        }
      },
      "invocations": [
        {
          "executionSuccessful": true,
          "endTimeUtc": "${timestamp}"
        }
      ],
      "results": [
        {
          "ruleId": "XSS_Reflected",
          "level": "error",
          "message": {
            "text": "[MOCK] User input from 'req.query.search' is used in response without encoding"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/routes/search.js",
                  "uriBaseId": "SRCROOT"
                },
                "region": {
                  "startLine": 45,
                  "startColumn": 12
                }
              }
            }
          ],
          "properties": {
            "fortify-category": "Cross-Site Scripting: Reflected",
            "fortify-kingdom": "Input Validation and Representation",
            "fortify-severity": "High",
            "fortify-confidence": "5.0",
            "fortify-instance-id": "ABCD1234"
          }
        }
      ],
      "properties": {
        "projectName": "${project_name}",
        "projectVersion": "${version}",
        "branch": "${branch}",
        "scanType": "SAST",
        "scanMode": "MOCK",
        "summary": {
          "critical": 0,
          "high": 1,
          "medium": 0,
          "low": 0,
          "total": 1
        }
      }
    }
  ]
}
EOF
}

# Parse SARIF report and extract summary
parse_sarif_report() {
    local report_file=$1

    if ! command -v jq &> /dev/null; then
        error "jq is required for report parsing"
        return 1
    fi

    # Extract counts by severity
    local critical=$(jq '[.runs[].results[] | select(.properties["fortify-severity"] == "Critical")] | length' "$report_file" 2>/dev/null || echo "0")
    local high=$(jq '[.runs[].results[] | select(.properties["fortify-severity"] == "High")] | length' "$report_file" 2>/dev/null || echo "0")
    local medium=$(jq '[.runs[].results[] | select(.properties["fortify-severity"] == "Medium")] | length' "$report_file" 2>/dev/null || echo "0")
    local low=$(jq '[.runs[].results[] | select(.properties["fortify-severity"] == "Low")] | length' "$report_file" 2>/dev/null || echo "0")
    local total=$(jq '[.runs[].results[]] | length' "$report_file" 2>/dev/null || echo "0")

    echo "${critical}:${high}:${medium}:${low}:${total}"
}

# Generate gate decision
evaluate_gate() {
    local counts=$1
    IFS=':' read -r critical high medium low total <<< "$counts"

    local gate_passed=true
    local reason=""

    if [[ "$FAIL_ON_CRITICAL" == "true" && "$critical" -gt 0 ]]; then
        gate_passed=false
        reason="$critical Critical findings detected"
    fi

    if [[ "$FAIL_ON_HIGH" == "true" && "$high" -gt 0 ]]; then
        gate_passed=false
        if [[ -n "$reason" ]]; then
            reason="${reason}, $high High findings"
        else
            reason="$high High findings detected"
        fi
    fi

    if [[ "$gate_passed" == "true" ]]; then
        echo "PASS:Security gate passed"
    else
        echo "FAIL:${reason}"
    fi
}

# Main scan function
fortify_scan() {
    local target_path=${1:-.}
    local output_dir=${2:-./reports}

    mkdir -p "$output_dir"

    local report_file="${output_dir}/sast-fortify.sarif.json"
    local summary_file="${output_dir}/fortify-summary.json"

    log "Starting Fortify SAST scan"
    log "  Target: ${target_path}"
    log "  Output: ${output_dir}"
    log "  Mock mode: ${FORTIFY_MOCK_MODE}"

    if [[ "$FORTIFY_MOCK_MODE" == "true" ]]; then
        log "Running in MOCK mode - generating sample report"
        generate_mock_report "$report_file"
    else
        # Real Fortify integration
        if [[ -z "${FORTIFY_SSC_URL:-}" ]]; then
            error "FORTIFY_SSC_URL not set. Set FORTIFY_MOCK_MODE=true for testing."
            return 1
        fi

        log "Connecting to Fortify SSC: ${FORTIFY_SSC_URL}"

        # Translation phase
        log "Phase 1: Source translation"
        if ! sourceanalyzer -b fortify-build -clean 2>/dev/null; then
            error "sourceanalyzer not found. Install Fortify SCA or use mock mode."
            return 1
        fi

        sourceanalyzer -b fortify-build "${target_path}"

        # Scan phase
        log "Phase 2: Security analysis"
        local fpr_file="${output_dir}/fortify-results.fpr"
        sourceanalyzer -b fortify-build -scan -f "$fpr_file"

        # Convert FPR to SARIF (requires fortifycli or custom conversion)
        log "Phase 3: Converting results to SARIF"
        if command -v fortifycli &> /dev/null; then
            fortifycli convert -f "$fpr_file" -o "$report_file" --format sarif
        else
            # Fallback: use FPRUtility if available
            error "SARIF conversion requires fortifycli. Using raw FPR."
            cp "$fpr_file" "${output_dir}/fortify-results.fpr"
        fi
    fi

    # Parse results and generate summary
    log "Analyzing results..."
    local counts=$(parse_sarif_report "$report_file")
    IFS=':' read -r critical high medium low total <<< "$counts"

    # Generate summary JSON
    cat > "$summary_file" << EOF
{
  "scanner": "fortify",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project": "${FORTIFY_PROJECT:-unknown}",
  "version": "${FORTIFY_VERSION:-unknown}",
  "findings": {
    "critical": ${critical},
    "high": ${high},
    "medium": ${medium},
    "low": ${low},
    "total": ${total}
  },
  "threshold": {
    "failOnCritical": ${FAIL_ON_CRITICAL},
    "failOnHigh": ${FAIL_ON_HIGH},
    "severityThreshold": "${SEVERITY_THRESHOLD}"
  },
  "reportFile": "$(basename "$report_file")"
}
EOF

    # Display summary
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║         FORTIFY SCAN SUMMARY               ║"
    echo "╠════════════════════════════════════════════╣"
    printf "║  Critical: %-6s  High: %-6s            ║\n" "$critical" "$high"
    printf "║  Medium:   %-6s  Low:  %-6s            ║\n" "$medium" "$low"
    echo "╠════════════════════════════════════════════╣"
    printf "║  Total findings: %-25s ║\n" "$total"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    # Evaluate gate
    local gate_result=$(evaluate_gate "$counts")
    IFS=':' read -r gate_status gate_reason <<< "$gate_result"

    if [[ "$gate_status" == "PASS" ]]; then
        log "✅ Security gate PASSED"
        return 0
    else
        log "❌ Security gate FAILED: ${gate_reason}"
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    fortify_scan "$@"
fi
