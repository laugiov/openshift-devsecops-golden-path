# Dynamic Application Security Testing (DAST)

This document describes the DAST integration using OWASP ZAP for runtime security testing.

## Overview

DAST scans test running applications for security vulnerabilities by simulating attacks against live endpoints.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DAST Pipeline Flow                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│  │   Deploy    │────▶│  OWASP ZAP  │────▶│   Report    │           │
│  │  to Stage   │     │    Scan     │     │  Analysis   │           │
│  └─────────────┘     └─────────────┘     └─────────────┘           │
│         │                   │                   │                   │
│         ▼                   ▼                   ▼                   │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐           │
│  │  Wait for   │     │  Baseline/  │     │   SARIF     │           │
│  │  Readiness  │     │  API/Full   │     │   Output    │           │
│  └─────────────┘     └─────────────┘     └─────────────┘           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Scan Types

| Type | Duration | Coverage | Use Case |
|------|----------|----------|----------|
| **Baseline** | 1-2 min | Passive only | CI/CD gates, quick feedback |
| **API** | 5-15 min | API endpoints | REST/GraphQL services |
| **Full** | 30-60+ min | Active attacks | Pre-release, penetration test |

## Quick Start

### Command Line

```bash
# Run baseline scan (mock mode for testing)
ZAP_MOCK_MODE=true ./scripts/scanners/dast/zap-scan.sh https://myapp.example.com

# Run baseline scan (real scan)
./scripts/scanners/dast/zap-scan.sh https://myapp-staging.example.com ./reports baseline

# Run API scan
./scripts/scanners/dast/zap-scan.sh https://api.example.com/v1 ./reports api

# Run full scan
./scripts/scanners/dast/zap-scan.sh https://myapp-staging.example.com ./reports full
```

### Jenkins Pipeline

```groovy
// In Jenkinsfile
stage('DAST Scan') {
    when {
        branch 'main'
    }
    steps {
        // Deploy to staging first
        script {
            def stagingUrl = deployToStaging()

            // Wait for deployment
            timeout(time: 5, unit: 'MINUTES') {
                waitUntil {
                    def response = httpRequest url: "${stagingUrl}/health", validResponseCodes: '200'
                    return response.status == 200
                }
            }

            // Run DAST scan
            dastScan(
                targetUrl: stagingUrl,
                scanType: 'baseline',
                failOnHigh: true,
                failOnMedium: false
            )
        }
    }
}
```

### GitLab CI

```yaml
dast:
  stage: security
  image: docker:latest
  services:
    - docker:dind
  variables:
    ZAP_IMAGE: ghcr.io/zaproxy/zaproxy:stable
  script:
    - |
      docker run --rm \
        -v $(pwd)/reports:/zap/wrk:rw \
        $ZAP_IMAGE \
        zap-baseline.py \
        -t "$STAGING_URL" \
        -J zap-report.json \
        -r zap-report.html \
        -I
  artifacts:
    paths:
      - reports/
    reports:
      sast: reports/dast-zap.sarif.json
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ZAP_IMAGE` | ZAP Docker image | `ghcr.io/zaproxy/zaproxy:stable` |
| `ZAP_MOCK_MODE` | Use mock reports | `false` |
| `ZAP_RULES_FILE` | Custom rules config | - |
| `ZAP_CONTEXT_FILE` | Auth context file | - |
| `FAIL_ON_HIGH` | Fail on high severity | `true` |
| `FAIL_ON_MEDIUM` | Fail on medium severity | `false` |

### Custom Rules Configuration

Create a rules file to customize scan behavior:

```
# zap-rules.conf
# Ignore specific alerts
10010	IGNORE	(Cookie No HttpOnly Flag)
10020	WARN	(X-Frame-Options)
40012	FAIL	(XSS Reflected)
```

```bash
ZAP_RULES_FILE=./zap-rules.conf ./scripts/scanners/dast/zap-scan.sh https://app.example.com
```

### Authentication Context

For authenticated scans, create a ZAP context file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <context>
        <name>MyApp</name>
        <authentication>
            <type>2</type>
            <form>
                <loginUrl>https://app.example.com/login</loginUrl>
                <loginRequestData>username={%username%}&amp;password={%password%}</loginRequestData>
            </form>
        </authentication>
        <users>
            <user>
                <name>testuser</name>
                <credentials>
                    <username>test@example.com</username>
                    <password>${ZAP_USER_PASSWORD}</password>
                </credentials>
            </user>
        </users>
    </context>
</configuration>
```

## Report Format

### SARIF Output

Reports are generated in SARIF format for integration with CI/CD tools:

```json
{
  "version": "2.1.0",
  "runs": [{
    "tool": {
      "driver": {
        "name": "OWASP ZAP",
        "version": "2.14.0"
      }
    },
    "results": [{
      "ruleId": "10020",
      "level": "warning",
      "message": {
        "text": "X-Frame-Options header is not included"
      },
      "locations": [{
        "physicalLocation": {
          "artifactLocation": {
            "uri": "https://app.example.com/"
          }
        }
      }],
      "properties": {
        "zap-risk": "Medium",
        "zap-solution": "Set X-Frame-Options header to DENY or SAMEORIGIN"
      }
    }]
  }]
}
```

### Summary JSON

```json
{
  "scanner": "owasp-zap",
  "scanType": "baseline",
  "timestamp": "2024-01-15T14:30:00Z",
  "target": "https://app.example.com",
  "findings": {
    "high": 0,
    "medium": 2,
    "low": 3,
    "total": 5
  },
  "threshold": {
    "failOnHigh": true,
    "failOnMedium": false
  }
}
```

## Common Findings

### High Severity

| Alert | Description | Remediation |
|-------|-------------|-------------|
| SQL Injection | User input in SQL queries | Use parameterized queries |
| XSS (Reflected) | User input in HTML output | Encode output, use CSP |
| Remote Code Execution | Command injection | Validate/sanitize input |

### Medium Severity

| Alert | Description | Remediation |
|-------|-------------|-------------|
| X-Frame-Options Missing | Clickjacking risk | Add header: `DENY` or `SAMEORIGIN` |
| CSP Not Set | No Content Security Policy | Implement CSP header |
| CSRF Tokens Missing | Cross-site request forgery | Add CSRF protection |

### Low Severity

| Alert | Description | Remediation |
|-------|-------------|-------------|
| Cookie No HttpOnly | XSS can steal cookies | Add HttpOnly flag |
| Server Header | Version disclosure | Remove or mask header |
| X-Content-Type-Options | MIME sniffing | Add `nosniff` header |

## Pipeline Integration

### Pre-Production Gate

```groovy
pipeline {
    stages {
        // ... build and deploy stages ...

        stage('DAST Gate') {
            steps {
                script {
                    def result = dastScan(
                        targetUrl: "${STAGING_URL}",
                        scanType: 'api',
                        failOnHigh: true
                    )

                    if (result.findings.high > 0) {
                        error "DAST found ${result.findings.high} high severity issues"
                    }
                }
            }
        }

        stage('Promote to Production') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                // Deploy to production
            }
        }
    }
}
```

### Parallel Security Scans

```groovy
stage('Security Scans') {
    parallel {
        stage('SAST') {
            steps {
                sastScan(tool: 'semgrep')
            }
        }
        stage('Container Scan') {
            steps {
                containerScan(image: "${IMAGE_NAME}:${IMAGE_TAG}")
            }
        }
        stage('DAST') {
            steps {
                dastScan(targetUrl: "${STAGING_URL}")
            }
        }
    }
}
```

## Troubleshooting

### Scan Times Out

- Use baseline scan for CI/CD (faster)
- Increase timeout for full scans
- Exclude non-critical paths with rules file

### Cannot Reach Target

- Verify network connectivity from Jenkins/runner
- Check firewall rules
- Use staging environment accessible from CI

### False Positives

- Create rules file to ignore specific alerts
- Use ZAP context for better accuracy
- Review and triage findings

### Authentication Issues

- Verify login URL and credentials
- Check session handling
- Use ZAP context file for complex auth

## References

- [OWASP ZAP Documentation](https://www.zaproxy.org/docs/)
- [ZAP Docker Images](https://www.zaproxy.org/docs/docker/)
- [SARIF Specification](https://sarifweb.azurewebsites.net/)
- [ZAP Baseline Scan](https://www.zaproxy.org/docs/docker/baseline-scan/)
