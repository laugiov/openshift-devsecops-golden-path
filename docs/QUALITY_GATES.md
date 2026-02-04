# Quality Gates Reference

This document explains the quality gates enforced by the Golden Path pipeline.

## Overview

Quality gates are checkpoints that must pass before code can proceed. They enforce:

- Code quality standards
- Security requirements
- Test coverage thresholds
- Vulnerability limits

## Gate Types

### 1. SonarQube Quality Gate

**What it checks:**
- Code smells
- Bugs
- Vulnerabilities
- Security hotspots
- Duplicated code
- Test coverage

**Default thresholds:**

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Bugs | 0 | No new bugs introduced |
| Vulnerabilities | 0 | No new security issues |
| Code Smells | A rating | Maintainable code |
| Coverage | 80% | Adequate test coverage |
| Duplications | 3% | Minimal copy-paste |

**Configuration:**

```properties
# sonar-project.properties
sonar.projectKey=my-service
sonar.sources=src
sonar.tests=test
sonar.javascript.lcov.reportPaths=coverage/lcov.info
```

### 2. SAST Gate (Static Analysis)

**What it checks:**
- Injection vulnerabilities (SQL, XSS, etc.)
- Authentication issues
- Cryptographic weaknesses
- Hardcoded secrets

**Tools:**
- Default: Semgrep
- Enterprise: Fortify, Checkmarx (via adapters)

**Default thresholds:**

| Severity | Threshold |
|----------|-----------|
| Critical | 0 |
| High | 0 |
| Medium | Warn only |
| Low | Ignored |

**Configuration:**

```yaml
# security/scanning/sast-config.yaml
rules:
  - id: sql-injection
    severity: critical
  - id: xss
    severity: high
```

### 3. SCA Gate (Dependency Scanning)

**What it checks:**
- Known vulnerabilities in dependencies
- Outdated packages
- License compliance

**Tools:**
- Trivy (container + dependencies)
- Grype (alternative)

**Default thresholds:**

| Severity | Threshold |
|----------|-----------|
| Critical | 0 |
| High | 5 (configurable) |
| Medium | Warn only |
| Low | Ignored |

**Configuration:**

```yaml
# security/scanning/sca-config.yaml
trivy:
  severity: CRITICAL,HIGH
  ignore-unfixed: true
  timeout: 10m
```

### 4. Secrets Detection Gate

**What it checks:**
- API keys
- Passwords
- Private keys
- Tokens

**Tools:**
- Gitleaks
- TruffleHog (alternative)

**Threshold:** 0 findings (any secret blocks)

**Configuration:**

```toml
# .gitleaks.toml
[allowlist]
description = "Allowed patterns"
paths = [
    '''\.env\.example''',
    '''test/fixtures/'''
]
```

### 5. Coverage Gate

**What it checks:**
- Line coverage
- Branch coverage

**Threshold:** 80% minimum (configurable)

## Gate Behavior

### Pass
Pipeline continues to next stage.

### Fail
Pipeline stops. Artifact not published. Developer must fix issues.

### Warn
Pipeline continues with warnings logged. Does not block but is reported.

## Bypassing Gates

Gates should not be bypassed casually. When necessary:

1. **Temporary bypass**: Use the [exception workflow](../security/exceptions/EXCEPTION_WORKFLOW.md)
2. **False positive**: Add to ignore file with justification comment
3. **Policy change**: Request threshold adjustment through security team

## Customization

### Per-Service Overrides

```groovy
// Jenkinsfile
goldenPipeline(
    appName: 'my-service',
    coverageThreshold: 70,     // Lower threshold for legacy
    criticalVulns: 0,          // Still zero critical
    highVulns: 10              // Higher tolerance for high
)
```

### Global Defaults

Modify in shared library configuration:

```yaml
# jenkins-shared-library/resources/default-config.yaml
quality:
  coverage: 80
  vulnerabilities:
    critical: 0
    high: 5
```

## Monitoring Gate Results

### Jenkins
- Gate results visible in build log
- Summary in build description
- Trends in job dashboard

### SonarQube
- Detailed analysis dashboard
- Historical trends
- Project comparison

### Security Dashboard
- Aggregated vulnerability counts
- Trends across services
- Compliance status
