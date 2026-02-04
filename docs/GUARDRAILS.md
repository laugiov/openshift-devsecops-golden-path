# Security Guardrails

This document defines the security controls enforced by the Golden Path pipeline. These guardrails are **mandatory** - they block, not warn.

---

## Philosophy

> "A warning is a suggestion. A block is a control."

In regulated environments, optional security doesn't work. This framework enforces guardrails at build time so violations never reach production.

---

## Pipeline Guardrails

### G-001: Static Application Security Testing (SAST)

**Tool:** Semgrep
**Default Threshold:** Block on HIGH and CRITICAL

| Severity | Default Action | Configurable |
|----------|----------------|--------------|
| CRITICAL | Block | No |
| HIGH | Block | Yes (can lower to block-on-critical) |
| MEDIUM | Warn | Yes |
| LOW | Ignore | Yes |

**What it catches:**
- SQL injection
- Command injection
- XSS vulnerabilities
- Insecure cryptography
- Hardcoded secrets (patterns)

**Configuration:**
```groovy
securityConfig: [
    sast: [
        enabled: true,
        tool: 'semgrep',
        failOn: 'high'  // 'critical', 'high', 'medium'
    ]
]
```

**Bypass:** Requires approved security exception.

---

### G-002: Software Composition Analysis (SCA)

**Tool:** Trivy
**Default Threshold:** Block on CRITICAL

| Severity | Default Action | Configurable |
|----------|----------------|--------------|
| CRITICAL | Block | No |
| HIGH | Warn | Yes (can escalate to block) |
| MEDIUM | Ignore | Yes |
| LOW | Ignore | Yes |

**What it catches:**
- Known CVEs in dependencies
- Vulnerable OS packages
- Outdated libraries with security issues

**Configuration:**
```groovy
securityConfig: [
    sca: [
        enabled: true,
        tool: 'trivy',
        failOn: 'critical'
    ]
]
```

**Bypass:** Requires approved security exception with remediation plan.

---

### G-003: Secrets Detection

**Tool:** Gitleaks
**Default Threshold:** Block on ANY finding

| Finding | Action | Configurable |
|---------|--------|--------------|
| Any secret pattern | Block | No |
| Entropy-based detection | Block | Yes |

**What it catches:**
- AWS keys
- API tokens
- Passwords
- Private keys
- Database credentials

**Configuration:**
```groovy
securityConfig: [
    secrets: [
        enabled: true,
        tool: 'gitleaks'
    ]
]
```

**Bypass:** Only for false positives, added to `.gitleaks.toml` with justification.

**CRITICAL:** If real secrets are detected, they must be rotated immediately regardless of deployment status.

---

### G-004: Quality Gate

**Tool:** SonarQube
**Default Threshold:** Must pass quality gate

| Metric | Default Threshold | Configurable |
|--------|-------------------|--------------|
| Coverage on new code | 80% | Yes (min 60%) |
| Duplicated lines | <3% | Yes |
| Maintainability rating | A | Yes |
| Reliability rating | A | No |
| Security rating | A | No |

**What it catches:**
- Untested code
- Code smells
- Bugs (static analysis)
- Technical debt
- Security hotspots

**Configuration:**
```groovy
qualityGate: [
    enabled: true,
    sonarProject: 'my-project',
    waitForQualityGate: true
]
```

**Bypass:** Not recommended. Quality gate failures indicate real issues.

---

## Container Guardrails

### G-010: Image Security

**Enforced at:** Build time

| Rule | Enforcement | Reason |
|------|-------------|--------|
| Non-root user | Required | Principle of least privilege |
| Read-only filesystem | Recommended | Prevent runtime modification |
| No privileged mode | Required | Container isolation |
| Specific base image version | Required | Reproducibility |

**Dockerfile requirements:**
```dockerfile
# Must specify version, not 'latest'
FROM node:20-alpine

# Must run as non-root
USER appuser

# Should use read-only root filesystem
# (Enabled via Kubernetes securityContext)
```

---

### G-011: Image Signing

**Tool:** Cosign
**Enforcement:** All images signed before push

**What it provides:**
- Cryptographic proof of origin
- Tamper detection
- Non-repudiation

**Verification:**
```bash
cosign verify --key cosign.pub registry/image@sha256:...
```

---

### G-012: SBOM Generation

**Tool:** CycloneDX
**Enforcement:** All images have accompanying SBOM

**What it provides:**
- Complete dependency inventory
- License compliance
- Vulnerability tracking
- Audit evidence

**Storage:** Attached to image as attestation

---

## Deployment Guardrails

### G-020: Environment Promotion

| Environment | Deployment Method | Approval Required |
|-------------|-------------------|-------------------|
| DEV | Auto-sync | None |
| QA | Manual sync | Team review |
| PROD | Manual sync | Lead + Security |

**Enforced via:** Git branch protection + Argo CD sync policies

---

### G-021: Image Immutability

**Rule:** Production must use digest references

```yaml
# Correct (immutable)
image:
  repository: registry/myapp
  digest: sha256:abc123...

# Incorrect (mutable)
image:
  repository: registry/myapp
  tag: latest
```

**Enforcement:** Pipeline fails if PROD promotion uses tag instead of digest.

---

### G-022: Resource Limits

**Rule:** All deployments must specify resource limits

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Enforcement:** Helm chart validation fails without limits.

---

## Network Guardrails

### G-030: Default Deny

**Recommendation:** NetworkPolicies with default deny

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

---

## Exception Process

When guardrails must be bypassed:

1. **Create Exception Request**
   - Use template in `security/exceptions/`
   - Document business justification
   - Include risk assessment

2. **Get Approval**
   - Security Lead for MEDIUM risk
   - CISO for HIGH risk
   - Security + Business Owner for CRITICAL

3. **Time-box**
   - Maximum 90 days
   - Must have remediation plan
   - Reviewed monthly

4. **Track**
   - Exception stored in Git
   - Regular review meetings
   - Metrics on exception count/age

---

## Audit Evidence

Each guardrail generates evidence:

| Guardrail | Evidence Generated |
|-----------|-------------------|
| SAST | Semgrep JSON report |
| SCA | Trivy JSON report |
| Secrets | Gitleaks report |
| Quality Gate | SonarQube status |
| Image Signing | Cosign signature |
| SBOM | CycloneDX JSON |

Evidence is:
- Stored in Jenkins artifacts
- Linked to specific build
- Retained per compliance requirements

---

## Compliance Mapping

| Guardrail | PCI-DSS | SOC2 | ISO 27001 |
|-----------|---------|------|-----------|
| SAST | 6.5.x | CC7.1 | A.14.2.1 |
| SCA | 6.3.1 | CC7.1 | A.12.6.1 |
| Secrets | 8.2.1 | CC6.1 | A.9.4.3 |
| Quality Gate | 6.3.2 | CC8.1 | A.14.2.8 |
| Image Signing | 6.4.2 | CC7.2 | A.14.2.6 |
| SBOM | 6.3.1 | CC7.1 | A.12.6.1 |

---

## Metrics

Track guardrail effectiveness:

| Metric | Target | Why |
|--------|--------|-----|
| Builds blocked by security | Track trend | Indicates code quality |
| Time to remediate | <7 days HIGH, <30 days MEDIUM | Speed of response |
| Exception count | Minimize | Exceptions = risk |
| Exception age | <90 days | Prevent permanent bypasses |
| False positive rate | <5% | Tool accuracy |

---

## Contact

- **Security questions:** #security-support
- **Exception requests:** security-exceptions@acme.com
- **Pipeline issues:** #platform-support
