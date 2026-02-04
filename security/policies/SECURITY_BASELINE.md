# Security Baseline Policies

This document defines the security baseline requirements for all services using the Golden Path pipeline.

## Mandatory Security Controls

### 1. Static Application Security Testing (SAST)

All services must pass SAST scanning with zero high-severity findings.

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Critical findings | 0 | Pipeline blocks |
| High findings | 0 | Pipeline blocks |
| Medium findings | Track | Warning only |
| Low findings | Track | Informational |

**Tools:** Semgrep (default), Fortify/Checkmarx (enterprise)

### 2. Software Composition Analysis (SCA)

All dependencies must be scanned for known vulnerabilities.

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Critical CVEs | 0 | Pipeline blocks |
| High CVEs | 0 (or exception) | Pipeline blocks |
| CVSS >= 9.0 | 0 | Pipeline blocks |

**Tools:** Trivy (default), Checkmarx SCA (enterprise)

### 3. Secrets Detection

No secrets allowed in source code.

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Hardcoded secrets | 0 | Pipeline blocks |
| API keys | 0 | Pipeline blocks |
| Private keys | 0 | Pipeline blocks |

**Tools:** Gitleaks, TruffleHog

### 4. Container Security

All container images must meet security requirements.

| Requirement | Description |
|-------------|-------------|
| Base image | Approved base images only |
| Non-root | Containers must run as non-root |
| Read-only FS | Recommended for production |
| No privileged | Privileged mode forbidden |
| Signed | Images must be Cosign-signed |

### 5. Code Quality

Minimum quality standards enforced via SonarQube.

| Metric | Threshold |
|--------|-----------|
| Code coverage | >= 80% |
| Duplications | < 3% |
| Maintainability | A rating |
| Reliability | A rating |
| Security | A rating |

## Exception Process

When a security requirement cannot be met:

1. Create exception request in `security/exceptions/`
2. Document business justification
3. Define remediation timeline (max 90 days)
4. Get Security Lead approval
5. Track in Git for audit trail

See [EXCEPTION_WORKFLOW.md](../exceptions/EXCEPTION_WORKFLOW.md) for details.

## Compliance Mapping

| Control | PCI-DSS | SOC2 | ISO 27001 |
|---------|---------|------|-----------|
| SAST | 6.5.x | CC7.1 | A.14.2.1 |
| SCA | 6.3.1 | CC7.1 | A.14.2.1 |
| Secrets | 3.4 | CC6.1 | A.9.4.3 |
| Container | 6.2 | CC6.1 | A.14.2.5 |
| Quality | 6.3.2 | CC8.1 | A.14.2.8 |

## Review Cadence

- **Monthly**: Review exception status
- **Quarterly**: Update baseline thresholds
- **Annually**: Full policy review
