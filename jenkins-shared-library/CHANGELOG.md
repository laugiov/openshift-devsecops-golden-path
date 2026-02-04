# Changelog

All notable changes to the Golden Path Shared Library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Kubernetes image verification policy (Kyverno)
- SECURITY_SETUP.md documentation
- GitHub Actions CI workflow with security scanning
- Mermaid architecture diagrams in documentation
- `make demo-e2e` for quick project validation
- DAST scanning support (OWASP ZAP, Nuclei)
- Gradle wrapper for running Spock tests

### Changed
- Improved error handling in all pipeline steps
- Unified container runtime detection in containerUtils
- Enhanced test coverage for demo-service (93%)
- Updated documentation with interactive diagrams

### Fixed
- Groovy syntax error in gitopsPromote.groovy (backtick handling)
- Coverage thresholds aligned with actual test coverage

## [1.0.0] - 2024-02-04

### Added
- Initial release of Golden Path Pipeline
- Core pipeline steps:
  - `goldenPipeline` - Main entry point for standardized CI/CD
  - `buildImage` - Container image building with proper labels
  - `pushImage` - Registry push with retry logic
  - `securityScan` - SAST/SCA/Secrets scanning with adapter pattern
  - `qualityGate` - SonarQube integration
  - `generateSbom` - CycloneDX SBOM generation
  - `signImage` - Cosign image signing
  - `gitopsPromote` - GitOps promotion via PR
  - `notifySlack` - Slack notifications
  - `containerUtils` - Shared utilities

- Security scanning adapters:
  - SAST: Semgrep (default), Fortify, Checkmarx
  - SCA: Trivy (default), Grype, Snyk
  - Secrets: Gitleaks (default), TruffleHog

- Supply chain security:
  - SBOM generation in CycloneDX format
  - Cosign image signing (key-based and keyless)
  - SBOM attestation

- GitOps promotion:
  - Direct commit for DEV (auto-sync)
  - PR-based promotion for QA/PROD
  - Digest-based immutable references

- Exception workflow:
  - Emergency mode with audit logging
  - Time-boxed exceptions
  - Git-tracked exception requests

### Security
- All security gates are blocking by default
- Image digest validation before promotion
- Credential validation with warnings

---

## Upgrade Guide

### From 0.x to 1.0.0

Update your Jenkinsfile to use version-pinned library:

```groovy
// Before (floating)
@Library('golden-path@main') _

// After (pinned)
@Library('golden-path@v1.0.0') _
```

### Breaking Changes in 1.0.0

1. **Parameter renamed**: `serviceName` → `appName`
2. **Values file pattern**: `values.yaml` → `values-<app>.yaml`
3. **Credentials required**: Pipeline now validates credentials exist

### Migration Checklist

- [ ] Pin library version in Jenkinsfile
- [ ] Rename `serviceName` to `appName` if used
- [ ] Rename GitOps values files to `values-<appName>.yaml`
- [ ] Configure Jenkins credentials (see SECURITY_SETUP.md)
