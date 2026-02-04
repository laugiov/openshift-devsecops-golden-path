# Pipeline Observability

This document describes how to measure and monitor the health of CI/CD pipelines.

## DORA Metrics

The Golden Path pipeline tracks the four key DORA metrics:

| Metric | Description | Target |
|--------|-------------|--------|
| **Deployment Frequency** | How often code is deployed to production | Daily or on-demand |
| **Lead Time for Changes** | Time from commit to production | < 1 day |
| **Change Failure Rate** | % of deployments causing failures | < 15% |
| **Mean Time to Recovery** | Time to restore service after incident | < 1 hour |

## Pipeline SLOs

### Service Level Objectives

| SLO | Target | Measurement |
|-----|--------|-------------|
| Pipeline Success Rate | >= 99% on main branch | Successful builds / Total builds |
| Build Duration (P95) | <= 15 minutes | 95th percentile build time |
| Security Scan Time | <= 5 minutes | Time for all security scans |
| Deployment Time | <= 10 minutes | Time from build to running in env |

### Error Budget

```
Monthly Error Budget = 100% - 99% = 1% = ~7.2 hours

If pipeline failures exceed error budget:
1. Stop feature work
2. Prioritize pipeline reliability
3. Post-mortem on failures
```

## Metrics Export

### JSON Artifact

Each pipeline run exports metrics to `reports/pipeline-metrics.json`:

```json
{
  "build_id": "123",
  "app_name": "demo-service",
  "branch": "main",
  "timestamp": "2024-01-15T10:30:00Z",
  "duration_seconds": 420,
  "status": "success",
  "stages": {
    "checkout": {"duration_seconds": 5, "status": "success"},
    "build": {"duration_seconds": 60, "status": "success"},
    "test": {"duration_seconds": 90, "status": "success"},
    "security_sast": {"duration_seconds": 45, "status": "success"},
    "security_sca": {"duration_seconds": 30, "status": "success"},
    "security_secrets": {"duration_seconds": 15, "status": "success"},
    "build_image": {"duration_seconds": 120, "status": "success"},
    "sign_image": {"duration_seconds": 10, "status": "success"},
    "deploy_dev": {"duration_seconds": 45, "status": "success"}
  },
  "security": {
    "sast_findings": 0,
    "sca_findings": 2,
    "secrets_findings": 0,
    "blocked": false
  },
  "artifacts": {
    "image_digest": "sha256:abc123...",
    "sbom_generated": true,
    "signed": true
  }
}
```

### Prometheus Metrics

Export to Prometheus Pushgateway for real-time monitoring:

```bash
# Push metrics after pipeline completion
./scripts/metrics/push-metrics.sh
```

Metrics exposed:

```
# HELP ci_pipeline_duration_seconds Pipeline execution duration
# TYPE ci_pipeline_duration_seconds histogram
ci_pipeline_duration_seconds_bucket{app="demo-service",branch="main",le="300"} 45
ci_pipeline_duration_seconds_bucket{app="demo-service",branch="main",le="600"} 98
ci_pipeline_duration_seconds_bucket{app="demo-service",branch="main",le="900"} 100
ci_pipeline_duration_seconds_sum{app="demo-service",branch="main"} 42000
ci_pipeline_duration_seconds_count{app="demo-service",branch="main"} 100

# HELP ci_pipeline_status Pipeline completion status
# TYPE ci_pipeline_status counter
ci_pipeline_status{app="demo-service",branch="main",status="success"} 98
ci_pipeline_status{app="demo-service",branch="main",status="failed"} 2

# HELP ci_security_findings Security scan findings
# TYPE ci_security_findings gauge
ci_security_findings{app="demo-service",type="sast",severity="critical"} 0
ci_security_findings{app="demo-service",type="sast",severity="high"} 1
ci_security_findings{app="demo-service",type="sca",severity="critical"} 0
ci_security_findings{app="demo-service",type="sca",severity="high"} 3

# HELP ci_stage_duration_seconds Individual stage duration
# TYPE ci_stage_duration_seconds gauge
ci_stage_duration_seconds{app="demo-service",stage="build"} 60
ci_stage_duration_seconds{app="demo-service",stage="test"} 90
ci_stage_duration_seconds{app="demo-service",stage="security"} 90
```

### Structured Logs

Pipeline logs in JSON format for log aggregation:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "pipeline": "golden-path",
  "build_id": "123",
  "app": "demo-service",
  "stage": "security",
  "message": "SAST scan completed",
  "duration_ms": 45000,
  "findings": 0,
  "status": "passed"
}
```

## Dashboards

### Grafana Dashboard

Import the included dashboard: `monitoring/grafana/pipeline-dashboard.json`

Panels:
1. **Pipeline Success Rate** - Rolling 7-day success percentage
2. **Build Duration Trend** - P50, P90, P95 over time
3. **Stage Duration Heatmap** - Identify slow stages
4. **Security Findings** - Trend of findings by severity
5. **DORA Metrics** - Four key metrics visualization

### Alert Rules

```yaml
# Prometheus alerting rules
groups:
- name: pipeline-alerts
  rules:
  - alert: PipelineSuccessRateLow
    expr: |
      (
        sum(rate(ci_pipeline_status{status="success"}[24h]))
        /
        sum(rate(ci_pipeline_status[24h]))
      ) < 0.95
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: Pipeline success rate below 95%

  - alert: PipelineDurationHigh
    expr: |
      histogram_quantile(0.95,
        sum(rate(ci_pipeline_duration_seconds_bucket[1h])) by (le, app)
      ) > 900
    for: 30m
    labels:
      severity: warning
    annotations:
      summary: Pipeline P95 duration exceeds 15 minutes

  - alert: SecurityFindingsCritical
    expr: ci_security_findings{severity="critical"} > 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: Critical security findings detected
```

## Implementation

### Jenkins

Add to `goldenPipeline.groovy`:

```groovy
def exportMetrics(Map buildInfo) {
    def metrics = [
        build_id: env.BUILD_NUMBER,
        app_name: buildInfo.appName,
        branch: env.GIT_BRANCH,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        duration_seconds: currentBuild.duration / 1000,
        status: currentBuild.result?.toLowerCase() ?: 'success',
        stages: buildInfo.stageResults
    ]

    writeJSON file: 'reports/pipeline-metrics.json', json: metrics

    // Push to Prometheus if configured
    if (env.PUSHGATEWAY_URL) {
        sh "./scripts/metrics/push-metrics.sh"
    }
}
```

### GitLab CI

```yaml
.export_metrics:
  after_script:
    - |
      cat > reports/pipeline-metrics.json << EOF
      {
        "build_id": "${CI_PIPELINE_ID}",
        "app_name": "${APP_NAME}",
        "branch": "${CI_COMMIT_REF_NAME}",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "duration_seconds": ${CI_PIPELINE_DURATION:-0},
        "status": "${CI_JOB_STATUS}"
      }
      EOF
    - ./scripts/metrics/push-metrics.sh || true
```

## Continuous Improvement

### Weekly Review

1. Review pipeline success rate
2. Identify flaky tests
3. Analyze slow stages
4. Track security trend

### Monthly Report

Generate automated reports:

```bash
./scripts/metrics/generate-report.sh --month 2024-01
```

Report includes:
- DORA metrics summary
- SLO compliance
- Top failure reasons
- Recommendations

## Troubleshooting

### High Failure Rate

1. Check recent changes to pipeline
2. Review test stability
3. Verify infrastructure health
4. Check external dependencies

### Slow Pipelines

1. Profile stage durations
2. Check for resource contention
3. Review caching effectiveness
4. Consider parallel execution

### Missing Metrics

1. Verify Pushgateway connectivity
2. Check metric export script
3. Review Prometheus scrape config
4. Validate JSON format
