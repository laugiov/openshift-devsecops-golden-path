#!/bin/bash
# OWASP ZAP DAST Scanner
#
# Dynamic Application Security Testing using OWASP ZAP.
# Supports baseline, API, and full scan modes.
#
# Usage:
#   ./zap-scan.sh <target_url> <output_dir> [scan_type]
#
# Scan Types:
#   baseline - Quick passive scan (default, ~1-2 min)
#   api      - API scan for OpenAPI/Swagger endpoints
#   full     - Full active scan (longer, more thorough)
#
# Environment Variables:
#   ZAP_IMAGE          - ZAP Docker image (default: ghcr.io/zaproxy/zaproxy:stable)
#   ZAP_RULES_FILE     - Custom rules configuration
#   ZAP_CONTEXT_FILE   - Authentication context
#   ZAP_MOCK_MODE      - Set to "true" for testing without Docker
#   FAIL_ON_HIGH       - Fail on High severity (default: true)
#   FAIL_ON_MEDIUM     - Fail on Medium severity (default: false)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default configuration
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
ZAP_MOCK_MODE="${ZAP_MOCK_MODE:-false}"
FAIL_ON_HIGH="${FAIL_ON_HIGH:-true}"
FAIL_ON_MEDIUM="${FAIL_ON_MEDIUM:-false}"

log() {
    echo "[ZAP] $*"
}

error() {
    echo "[ZAP] ERROR: $*" >&2
}

# Generate mock DAST report for testing
generate_mock_report() {
    local output_file=$1
    local target_url=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "${output_file}" << EOF
{
  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "OWASP ZAP",
          "version": "2.14.0",
          "informationUri": "https://www.zaproxy.org/",
          "rules": [
            {
              "id": "10010",
              "name": "Cookie No HttpOnly Flag",
              "shortDescription": {
                "text": "Cookie set without HttpOnly flag"
              },
              "defaultConfiguration": {
                "level": "warning"
              },
              "properties": {
                "security-severity": "3.1",
                "tags": ["security", "cookies", "owasp-a05"]
              }
            },
            {
              "id": "10020",
              "name": "X-Frame-Options Header Missing",
              "shortDescription": {
                "text": "X-Frame-Options header not set"
              },
              "defaultConfiguration": {
                "level": "warning"
              },
              "properties": {
                "security-severity": "4.3",
                "tags": ["security", "headers", "clickjacking"]
              }
            },
            {
              "id": "40012",
              "name": "Cross-Site Scripting (Reflected)",
              "shortDescription": {
                "text": "Reflected XSS vulnerability"
              },
              "defaultConfiguration": {
                "level": "error"
              },
              "properties": {
                "security-severity": "6.1",
                "tags": ["security", "xss", "owasp-a03"]
              }
            },
            {
              "id": "90022",
              "name": "Application Error Disclosure",
              "shortDescription": {
                "text": "Application error messages disclosed"
              },
              "defaultConfiguration": {
                "level": "note"
              },
              "properties": {
                "security-severity": "2.5",
                "tags": ["security", "info-disclosure"]
              }
            }
          ]
        }
      },
      "invocations": [
        {
          "executionSuccessful": true,
          "commandLine": "zap-baseline.py -t ${target_url}",
          "endTimeUtc": "${timestamp}"
        }
      ],
      "results": [
        {
          "ruleId": "10020",
          "level": "warning",
          "message": {
            "text": "[MOCK] X-Frame-Options header is not included in the HTTP response"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "${target_url}/"
                }
              }
            }
          ],
          "properties": {
            "zap-alertRef": "10020",
            "zap-confidence": "Medium",
            "zap-risk": "Medium",
            "zap-solution": "Set X-Frame-Options header to DENY or SAMEORIGIN"
          }
        },
        {
          "ruleId": "10010",
          "level": "warning",
          "message": {
            "text": "[MOCK] Cookie set without HttpOnly flag: session_id"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "${target_url}/api/login"
                }
              }
            }
          ],
          "properties": {
            "zap-alertRef": "10010",
            "zap-confidence": "Medium",
            "zap-risk": "Low",
            "zap-solution": "Ensure the HttpOnly flag is set for all cookies"
          }
        },
        {
          "ruleId": "90022",
          "level": "note",
          "message": {
            "text": "[MOCK] Application error message disclosed in response"
          },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {
                  "uri": "${target_url}/api/error"
                }
              }
            }
          ],
          "properties": {
            "zap-alertRef": "90022",
            "zap-confidence": "Medium",
            "zap-risk": "Low"
          }
        }
      ],
      "properties": {
        "targetUrl": "${target_url}",
        "scanType": "baseline",
        "scanMode": "MOCK",
        "summary": {
          "high": 0,
          "medium": 2,
          "low": 1,
          "informational": 0,
          "total": 3
        }
      }
    }
  ]
}
EOF
}

# Convert ZAP JSON to SARIF format
convert_to_sarif() {
    local zap_json=$1
    local sarif_file=$2
    local target_url=$3

    if ! command -v jq &> /dev/null; then
        error "jq is required for report conversion"
        return 1
    fi

    jq --arg url "$target_url" '
    {
      "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
      "version": "2.1.0",
      "runs": [{
        "tool": {
          "driver": {
            "name": "OWASP ZAP",
            "version": .["@version"] // "unknown",
            "informationUri": "https://www.zaproxy.org/",
            "rules": [.site[].alerts[] | {
              "id": .pluginid,
              "name": .alert,
              "shortDescription": {"text": .alert},
              "properties": {
                "security-severity": (
                  if .riskcode == "3" then "9.0"
                  elif .riskcode == "2" then "6.0"
                  elif .riskcode == "1" then "3.0"
                  else "1.0" end
                )
              }
            }] | unique_by(.id)
          }
        },
        "results": [.site[].alerts[] | . as $alert | .instances[] | {
          "ruleId": $alert.pluginid,
          "level": (
            if $alert.riskcode == "3" then "error"
            elif $alert.riskcode == "2" then "warning"
            else "note" end
          ),
          "message": {"text": $alert.alert},
          "locations": [{
            "physicalLocation": {
              "artifactLocation": {"uri": .uri}
            }
          }],
          "properties": {
            "zap-confidence": $alert.confidence,
            "zap-risk": (
              if $alert.riskcode == "3" then "High"
              elif $alert.riskcode == "2" then "Medium"
              elif $alert.riskcode == "1" then "Low"
              else "Informational" end
            ),
            "zap-solution": $alert.solution
          }
        }],
        "properties": {
          "targetUrl": $url,
          "summary": {
            "high": [.site[].alerts[] | select(.riskcode == "3")] | length,
            "medium": [.site[].alerts[] | select(.riskcode == "2")] | length,
            "low": [.site[].alerts[] | select(.riskcode == "1")] | length,
            "informational": [.site[].alerts[] | select(.riskcode == "0")] | length
          }
        }
      }]
    }' "$zap_json" > "$sarif_file"
}

# Parse SARIF report and extract summary
parse_sarif_report() {
    local report_file=$1

    local high=$(jq '[.runs[].results[] | select(.level == "error")] | length' "$report_file" 2>/dev/null || echo "0")
    local medium=$(jq '[.runs[].results[] | select(.level == "warning")] | length' "$report_file" 2>/dev/null || echo "0")
    local low=$(jq '[.runs[].results[] | select(.level == "note")] | length' "$report_file" 2>/dev/null || echo "0")
    local total=$(jq '[.runs[].results[]] | length' "$report_file" 2>/dev/null || echo "0")

    echo "${high}:${medium}:${low}:${total}"
}

# Evaluate security gate
evaluate_gate() {
    local counts=$1
    IFS=':' read -r high medium low total <<< "$counts"

    local gate_passed=true
    local reason=""

    if [[ "$FAIL_ON_HIGH" == "true" && "$high" -gt 0 ]]; then
        gate_passed=false
        reason="$high High severity findings"
    fi

    if [[ "$FAIL_ON_MEDIUM" == "true" && "$medium" -gt 0 ]]; then
        gate_passed=false
        if [[ -n "$reason" ]]; then
            reason="${reason}, $medium Medium findings"
        else
            reason="$medium Medium severity findings"
        fi
    fi

    if [[ "$gate_passed" == "true" ]]; then
        echo "PASS:Security gate passed"
    else
        echo "FAIL:${reason}"
    fi
}

# Run ZAP baseline scan
run_baseline_scan() {
    local target_url=$1
    local output_dir=$2

    log "Running baseline scan..."

    docker run --rm \
        -v "${output_dir}:/zap/wrk:rw" \
        -t "${ZAP_IMAGE}" \
        zap-baseline.py \
        -t "${target_url}" \
        -J zap-report.json \
        -r zap-report.html \
        -w zap-report.md \
        ${ZAP_RULES_FILE:+-c "/zap/wrk/$(basename "$ZAP_RULES_FILE")"} \
        -I || true  # Don't fail on findings

    return 0
}

# Run ZAP API scan
run_api_scan() {
    local target_url=$1
    local output_dir=$2
    local api_spec=${3:-""}

    log "Running API scan..."

    local api_args=""
    if [[ -n "$api_spec" ]]; then
        api_args="-f openapi -O ${api_spec}"
    fi

    docker run --rm \
        -v "${output_dir}:/zap/wrk:rw" \
        -t "${ZAP_IMAGE}" \
        zap-api-scan.py \
        -t "${target_url}" \
        -J zap-report.json \
        -r zap-report.html \
        ${api_args} \
        -I || true

    return 0
}

# Run ZAP full scan
run_full_scan() {
    local target_url=$1
    local output_dir=$2

    log "Running full scan (this may take a while)..."

    docker run --rm \
        -v "${output_dir}:/zap/wrk:rw" \
        -t "${ZAP_IMAGE}" \
        zap-full-scan.py \
        -t "${target_url}" \
        -J zap-report.json \
        -r zap-report.html \
        ${ZAP_CONTEXT_FILE:+-n "/zap/wrk/$(basename "$ZAP_CONTEXT_FILE")"} \
        -I || true

    return 0
}

# Main function
zap_scan() {
    local target_url=${1:-""}
    local output_dir=${2:-"./reports/dast"}
    local scan_type=${3:-"baseline"}

    if [[ -z "$target_url" ]]; then
        error "Target URL is required"
        echo "Usage: $0 <target_url> [output_dir] [scan_type]"
        return 1
    fi

    mkdir -p "$output_dir"

    local report_file="${output_dir}/dast-zap.sarif.json"
    local summary_file="${output_dir}/zap-summary.json"

    log "Starting OWASP ZAP DAST scan"
    log "  Target: ${target_url}"
    log "  Scan type: ${scan_type}"
    log "  Output: ${output_dir}"
    log "  Mock mode: ${ZAP_MOCK_MODE}"

    if [[ "$ZAP_MOCK_MODE" == "true" ]]; then
        log "Running in MOCK mode - generating sample report"
        generate_mock_report "$report_file" "$target_url"
    else
        # Check Docker availability
        if ! command -v docker &> /dev/null; then
            error "Docker is required for ZAP scans"
            return 1
        fi

        # Run appropriate scan type
        case "$scan_type" in
            baseline)
                run_baseline_scan "$target_url" "$output_dir"
                ;;
            api)
                run_api_scan "$target_url" "$output_dir"
                ;;
            full)
                run_full_scan "$target_url" "$output_dir"
                ;;
            *)
                error "Unknown scan type: $scan_type"
                return 1
                ;;
        esac

        # Convert ZAP JSON to SARIF
        local zap_json="${output_dir}/zap-report.json"
        if [[ -f "$zap_json" ]]; then
            convert_to_sarif "$zap_json" "$report_file" "$target_url"
        else
            error "ZAP report not generated"
            return 1
        fi
    fi

    # Parse results and generate summary
    log "Analyzing results..."
    local counts
    counts=$(parse_sarif_report "$report_file")
    IFS=':' read -r high medium low total <<< "$counts"

    # Generate summary JSON
    cat > "$summary_file" << EOF
{
  "scanner": "owasp-zap",
  "scanType": "${scan_type}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "target": "${target_url}",
  "findings": {
    "high": ${high},
    "medium": ${medium},
    "low": ${low},
    "total": ${total}
  },
  "threshold": {
    "failOnHigh": ${FAIL_ON_HIGH},
    "failOnMedium": ${FAIL_ON_MEDIUM}
  },
  "reportFile": "$(basename "$report_file")"
}
EOF

    # Display summary
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║         OWASP ZAP SCAN SUMMARY             ║"
    echo "╠════════════════════════════════════════════╣"
    printf "║  High:   %-6s  Medium: %-6s            ║\n" "$high" "$medium"
    printf "║  Low:    %-6s  Total:  %-6s            ║\n" "$low" "$total"
    echo "╠════════════════════════════════════════════╣"
    printf "║  Target: %-32s ║\n" "${target_url:0:32}"
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
    zap_scan "$@"
fi
