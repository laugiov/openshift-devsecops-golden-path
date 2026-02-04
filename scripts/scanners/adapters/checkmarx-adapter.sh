#!/bin/bash
# Checkmarx SAST Adapter
#
# This adapter provides a standardized interface for Checkmarx integration.
# It supports both real Checkmarx One/CxSAST scans and mock mode for testing.
#
# Usage:
#   checkmarx_scan <target_path> <output_dir> [options]
#
# Options (via environment variables):
#   CX_BASE_URL         - Checkmarx server URL (CxOne or CxSAST)
#   CX_CLIENT_ID        - OAuth client ID (CxOne) or username (CxSAST)
#   CX_CLIENT_SECRET    - OAuth secret (CxOne) or password (CxSAST)
#   CX_TENANT           - Tenant name (CxOne only)
#   CX_PROJECT          - Project name
#   CX_BRANCH           - Branch to scan
#   CX_MOCK_MODE        - Set to "true" to use mock reports for testing
#   SEVERITY_THRESHOLD  - Minimum severity to report (Critical, High, Medium, Low)
#   FAIL_ON_CRITICAL    - Fail pipeline on Critical findings (default: true)
#   FAIL_ON_HIGH        - Fail pipeline on High findings (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default configuration
CX_MOCK_MODE="${CX_MOCK_MODE:-false}"
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
    echo "[Checkmarx] $*"
}

error() {
    echo "[Checkmarx] ERROR: $*" >&2
}

# Generate mock report for testing
generate_mock_report() {
    local output_file=$1
    local project_name=${CX_PROJECT:-demo-service}
    local branch=${CX_BRANCH:-main}
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "${output_file}" << EOF
{
  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "Checkmarx SAST",
          "version": "9.5.0",
          "informationUri": "https://checkmarx.com/product/cxsast-source-code-scanning/",
          "rules": [
            {
              "id": "CWE-89",
              "name": "SQL Injection",
              "shortDescription": {
                "text": "SQL Injection vulnerability"
              },
              "fullDescription": {
                "text": "The application constructs all or part of an SQL command using externally-influenced input."
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "9.8",
                "precision": "high",
                "tags": ["security", "sql", "injection", "owasp-a03"]
              }
            },
            {
              "id": "CWE-78",
              "name": "OS Command Injection",
              "shortDescription": {
                "text": "Command Injection vulnerability"
              },
              "fullDescription": {
                "text": "The application constructs OS commands using externally-influenced input."
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "9.8",
                "precision": "high",
                "tags": ["security", "command", "injection", "owasp-a03"]
              }
            },
            {
              "id": "CWE-502",
              "name": "Deserialization of Untrusted Data",
              "shortDescription": {
                "text": "Unsafe deserialization detected"
              },
              "fullDescription": {
                "text": "The application deserializes untrusted data without verification."
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "8.1",
                "precision": "medium",
                "tags": ["security", "deserialization", "owasp-a08"]
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
          "ruleId": "CWE-502",
          "level": "error",
          "message": {
            "text": "[MOCK] Unsafe JSON deserialization of user-controlled input"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/utils/parser.js",
                  "uriBaseId": "SRCROOT"
                },
                "region": {
                  "startLine": 23,
                  "startColumn": 5
                }
              }
            }
          ],
          "properties": {
            "checkmarx-query": "Deserialization_of_Untrusted_Data",
            "checkmarx-severity": "Medium",
            "checkmarx-state": "To Verify",
            "checkmarx-result-id": "12345678"
          }
        },
        {
          "ruleId": "CWE-89",
          "level": "warning",
          "message": {
            "text": "[MOCK] Potential SQL injection in database query"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "src/db/users.js",
                  "uriBaseId": "SRCROOT"
                },
                "region": {
                  "startLine": 87,
                  "startColumn": 12
                }
              }
            }
          ],
          "properties": {
            "checkmarx-query": "SQL_Injection",
            "checkmarx-severity": "Low",
            "checkmarx-state": "To Verify",
            "checkmarx-result-id": "12345679"
          }
        }
      ],
      "properties": {
        "projectName": "${project_name}",
        "branch": "${branch}",
        "scanType": "SAST",
        "scanMode": "MOCK",
        "summary": {
          "critical": 0,
          "high": 0,
          "medium": 1,
          "low": 1,
          "total": 2
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
    local critical=$(jq '[.runs[].results[] | select(.properties["checkmarx-severity"] == "Critical")] | length' "$report_file" 2>/dev/null || echo "0")
    local high=$(jq '[.runs[].results[] | select(.properties["checkmarx-severity"] == "High")] | length' "$report_file" 2>/dev/null || echo "0")
    local medium=$(jq '[.runs[].results[] | select(.properties["checkmarx-severity"] == "Medium")] | length' "$report_file" 2>/dev/null || echo "0")
    local low=$(jq '[.runs[].results[] | select(.properties["checkmarx-severity"] == "Low")] | length' "$report_file" 2>/dev/null || echo "0")
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

# Authenticate with Checkmarx One
cx_one_authenticate() {
    local auth_response
    auth_response=$(curl -s -X POST "${CX_BASE_URL}/auth/realms/${CX_TENANT}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=${CX_CLIENT_ID}" \
        -d "client_secret=${CX_CLIENT_SECRET}")

    echo "$auth_response" | jq -r '.access_token'
}

# Create scan in Checkmarx One
cx_one_create_scan() {
    local token=$1
    local source_path=$2
    local project_id=$3

    # First, upload source
    local upload_url
    upload_url=$(curl -s -X POST "${CX_BASE_URL}/api/uploads" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{}' | jq -r '.url')

    # Create zip and upload
    local zip_file="/tmp/cx-source-$$.zip"
    (cd "$source_path" && zip -r "$zip_file" . -x '*.git*' -x 'node_modules/*' -x 'vendor/*')
    curl -s -X PUT "$upload_url" -H "Content-Type: application/zip" --data-binary "@$zip_file"
    rm -f "$zip_file"

    # Create scan
    curl -s -X POST "${CX_BASE_URL}/api/scans" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"upload\",
            \"project\": {\"id\": \"${project_id}\"},
            \"config\": [{\"type\": \"sast\", \"value\": {}}],
            \"branch\": \"${CX_BRANCH:-main}\"
        }" | jq -r '.id'
}

# Wait for scan completion and get results
cx_one_wait_for_results() {
    local token=$1
    local scan_id=$2
    local max_wait=3600
    local waited=0

    log "Waiting for scan completion..."
    while [[ $waited -lt $max_wait ]]; do
        local status
        status=$(curl -s -X GET "${CX_BASE_URL}/api/scans/${scan_id}" \
            -H "Authorization: Bearer ${token}" | jq -r '.status')

        if [[ "$status" == "Completed" ]]; then
            log "Scan completed"
            return 0
        elif [[ "$status" == "Failed" || "$status" == "Canceled" ]]; then
            error "Scan ${status}"
            return 1
        fi

        sleep 30
        waited=$((waited + 30))
        log "Scan status: ${status} (waited ${waited}s)"
    done

    error "Scan timed out after ${max_wait}s"
    return 1
}

# Main scan function
checkmarx_scan() {
    local target_path=${1:-.}
    local output_dir=${2:-./reports}

    mkdir -p "$output_dir"

    local report_file="${output_dir}/sast-checkmarx.sarif.json"
    local summary_file="${output_dir}/checkmarx-summary.json"

    log "Starting Checkmarx SAST scan"
    log "  Target: ${target_path}"
    log "  Output: ${output_dir}"
    log "  Mock mode: ${CX_MOCK_MODE}"

    if [[ "$CX_MOCK_MODE" == "true" ]]; then
        log "Running in MOCK mode - generating sample report"
        generate_mock_report "$report_file"
    else
        # Real Checkmarx integration
        if [[ -z "${CX_BASE_URL:-}" ]]; then
            error "CX_BASE_URL not set. Set CX_MOCK_MODE=true for testing."
            return 1
        fi

        # Check for CxCLI (legacy) or use CxOne API
        if command -v CxConsolePlugin &> /dev/null; then
            log "Using CxSAST CLI"
            CxConsolePlugin Scan \
                -v \
                -CxServer "${CX_BASE_URL}" \
                -CxUser "${CX_CLIENT_ID}" \
                -CxPassword "${CX_CLIENT_SECRET}" \
                -ProjectName "${CX_PROJECT:-$(basename "$target_path")}" \
                -LocationType folder \
                -LocationPath "$target_path" \
                -ReportPDF "${output_dir}/checkmarx-report.pdf" \
                -ReportXML "${output_dir}/checkmarx-report.xml"

            # Convert XML to SARIF (simplified)
            log "Converting results to SARIF..."
            # In production, use a proper XML-to-SARIF converter
            error "XML to SARIF conversion not implemented. Please use CxOne or add converter."
            return 1
        else
            # CxOne API flow
            log "Using Checkmarx One API"

            local token
            token=$(cx_one_authenticate)
            if [[ -z "$token" || "$token" == "null" ]]; then
                error "Failed to authenticate with Checkmarx One"
                return 1
            fi

            # Get or create project
            local project_id
            project_id=$(curl -s -X GET "${CX_BASE_URL}/api/projects?name=${CX_PROJECT}" \
                -H "Authorization: Bearer ${token}" | jq -r '.projects[0].id // empty')

            if [[ -z "$project_id" ]]; then
                log "Creating new project: ${CX_PROJECT}"
                project_id=$(curl -s -X POST "${CX_BASE_URL}/api/projects" \
                    -H "Authorization: Bearer ${token}" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\": \"${CX_PROJECT}\"}" | jq -r '.id')
            fi

            # Create and run scan
            local scan_id
            scan_id=$(cx_one_create_scan "$token" "$target_path" "$project_id")

            # Wait for results
            cx_one_wait_for_results "$token" "$scan_id"

            # Download SARIF report
            curl -s -X GET "${CX_BASE_URL}/api/results/${scan_id}/sarif" \
                -H "Authorization: Bearer ${token}" \
                -o "$report_file"
        fi
    fi

    # Parse results and generate summary
    log "Analyzing results..."
    local counts
    counts=$(parse_sarif_report "$report_file")
    IFS=':' read -r critical high medium low total <<< "$counts"

    # Generate summary JSON
    cat > "$summary_file" << EOF
{
  "scanner": "checkmarx",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project": "${CX_PROJECT:-unknown}",
  "branch": "${CX_BRANCH:-unknown}",
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
    echo "║        CHECKMARX SCAN SUMMARY              ║"
    echo "╠════════════════════════════════════════════╣"
    printf "║  Critical: %-6s  High: %-6s            ║\n" "$critical" "$high"
    printf "║  Medium:   %-6s  Low:  %-6s            ║\n" "$medium" "$low"
    echo "╠════════════════════════════════════════════╣"
    printf "║  Total findings: %-25s ║\n" "$total"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    # Evaluate gate
    local gate_result
    gate_result=$(evaluate_gate "$counts")
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
    checkmarx_scan "$@"
fi
