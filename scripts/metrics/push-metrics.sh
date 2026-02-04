#!/bin/bash
# Push Pipeline Metrics to Prometheus Pushgateway
#
# Usage:
#   ./push-metrics.sh [metrics-file]
#
# Environment variables:
#   PUSHGATEWAY_URL  - Pushgateway URL (required)
#   APP_NAME         - Application name
#   BUILD_ID         - Build identifier
#   GIT_BRANCH       - Git branch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_FILE="${1:-reports/pipeline-metrics.json}"

# Configuration
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-}"
APP_NAME="${APP_NAME:-unknown}"
BUILD_ID="${BUILD_ID:-${CI_PIPELINE_ID:-${BUILD_NUMBER:-0}}}"
GIT_BRANCH="${GIT_BRANCH:-${CI_COMMIT_REF_NAME:-main}}"

log() {
    echo "[metrics] $*"
}

error() {
    echo "[metrics] ERROR: $*" >&2
}

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        error "jq is required for metrics parsing"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl is required for pushing metrics"
        exit 1
    fi
}

# Read metrics from JSON file
parse_metrics() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        log "Metrics file not found: $file"
        return 1
    fi

    # Extract values
    APP_NAME=$(jq -r '.app_name // "unknown"' "$file")
    BUILD_ID=$(jq -r '.build_id // "0"' "$file")
    BRANCH=$(jq -r '.branch // "main"' "$file")
    DURATION=$(jq -r '.duration_seconds // 0' "$file")
    STATUS=$(jq -r '.status // "unknown"' "$file")

    # Extract security findings if present
    SAST_FINDINGS=$(jq -r '.security.sast_findings // 0' "$file")
    SCA_FINDINGS=$(jq -r '.security.sca_findings // 0' "$file")
    SECRETS_FINDINGS=$(jq -r '.security.secrets_findings // 0' "$file")
}

# Generate Prometheus format metrics
generate_prometheus_metrics() {
    local timestamp
    timestamp=$(date +%s%3N)

    cat << EOF
# HELP ci_pipeline_duration_seconds Total pipeline duration in seconds
# TYPE ci_pipeline_duration_seconds gauge
ci_pipeline_duration_seconds{app="${APP_NAME}",branch="${BRANCH}"} ${DURATION}

# HELP ci_pipeline_status Pipeline completion status (1=success, 0=failed)
# TYPE ci_pipeline_status gauge
ci_pipeline_status{app="${APP_NAME}",branch="${BRANCH}",status="${STATUS}"} 1

# HELP ci_pipeline_build_info Pipeline build information
# TYPE ci_pipeline_build_info gauge
ci_pipeline_build_info{app="${APP_NAME}",branch="${BRANCH}",build_id="${BUILD_ID}"} 1

# HELP ci_security_findings_total Total security findings by type
# TYPE ci_security_findings_total gauge
ci_security_findings_total{app="${APP_NAME}",type="sast"} ${SAST_FINDINGS}
ci_security_findings_total{app="${APP_NAME}",type="sca"} ${SCA_FINDINGS}
ci_security_findings_total{app="${APP_NAME}",type="secrets"} ${SECRETS_FINDINGS}

# HELP ci_pipeline_last_success_timestamp Timestamp of last successful build
# TYPE ci_pipeline_last_success_timestamp gauge
EOF

    if [[ "$STATUS" == "success" ]]; then
        echo "ci_pipeline_last_success_timestamp{app=\"${APP_NAME}\",branch=\"${BRANCH}\"} ${timestamp}"
    fi
}

# Push metrics to Pushgateway
push_to_gateway() {
    local metrics=$1
    local job_name="${APP_NAME}-pipeline"

    log "Pushing metrics to ${PUSHGATEWAY_URL}"

    local response
    response=$(echo "$metrics" | curl -s -w "%{http_code}" \
        --data-binary @- \
        "${PUSHGATEWAY_URL}/metrics/job/${job_name}/instance/${BUILD_ID}")

    local http_code="${response: -3}"
    local body="${response:0:-3}"

    if [[ "$http_code" =~ ^2 ]]; then
        log "Metrics pushed successfully"
    else
        error "Failed to push metrics: HTTP ${http_code}"
        error "Response: ${body}"
        return 1
    fi
}

# Export metrics to JSON (for artifact collection)
export_to_json() {
    local output_file="${1:-reports/prometheus-metrics.txt}"

    log "Exporting metrics to ${output_file}"
    generate_prometheus_metrics > "$output_file"
}

# Main
main() {
    check_dependencies

    # Parse metrics from file
    if [[ -f "$METRICS_FILE" ]]; then
        parse_metrics "$METRICS_FILE"
    else
        log "Using environment variables for metrics"
        DURATION="${PIPELINE_DURATION:-0}"
        STATUS="${PIPELINE_STATUS:-unknown}"
        SAST_FINDINGS="${SAST_FINDINGS:-0}"
        SCA_FINDINGS="${SCA_FINDINGS:-0}"
        SECRETS_FINDINGS="${SECRETS_FINDINGS:-0}"
    fi

    # Generate metrics
    local metrics
    metrics=$(generate_prometheus_metrics)

    # Always export to file
    mkdir -p "$(dirname reports/prometheus-metrics.txt)"
    export_to_json "reports/prometheus-metrics.txt"

    # Push to gateway if configured
    if [[ -n "$PUSHGATEWAY_URL" ]]; then
        push_to_gateway "$metrics"
    else
        log "PUSHGATEWAY_URL not set, skipping push"
        log "Metrics exported to reports/prometheus-metrics.txt"
    fi
}

main "$@"
