# GitLab CI Pipeline Template

This directory contains the GitLab CI pipeline template that provides **parity with Jenkins shared library controls**.

## Key Principle

> Same scripts, same gates, same outputs - different CI engine.

This pipeline enforces the exact same security controls as the Jenkins pipeline:
- SAST scanning (Semgrep)
- SCA scanning (Trivy)
- Secrets detection (Gitleaks)
- Quality gates (SonarQube optional)
- Container image building with OCI labels
- SBOM generation (CycloneDX)
- Image signing (Cosign)
- GitOps promotion

## Usage

### Option 1: Copy to Repository Root

```bash
cp ci/gitlab/.gitlab-ci.yml .gitlab-ci.yml
```

### Option 2: Include from Central Repository

In your repository's `.gitlab-ci.yml`:

```yaml
include:
  - project: 'platform/golden-path'
    ref: main
    file: '/ci/gitlab/.gitlab-ci.yml'

variables:
  APP_NAME: my-service
  BUILD_TOOL: node
```

## Required Variables

Configure these in GitLab CI/CD Settings > Variables:

| Variable | Type | Description |
|----------|------|-------------|
| `REGISTRY_URL` | Variable | Container registry URL |
| `REGISTRY_USER` | Variable | Registry username |
| `REGISTRY_PASSWORD` | Variable (masked) | Registry password |
| `COSIGN_KEY` | File | Cosign private key |
| `COSIGN_PASSWORD` | Variable (masked) | Cosign key password |
| `GITOPS_SSH_KEY` | File | SSH key for GitOps repo |
| `GITOPS_REPO_URL` | Variable | GitOps repository URL |
| `SONAR_TOKEN` | Variable (masked) | SonarQube token (optional) |
| `SONAR_HOST_URL` | Variable | SonarQube URL (optional) |

## Pipeline Stages

```
build → test → security → quality → package → sign → publish → deploy
```

### Stage Details

| Stage | Jobs | Gate Behavior |
|-------|------|---------------|
| build | Build application | Fail on error |
| test | Unit tests, lint | Fail on error |
| security | SAST, SCA, Secrets | **Block on HIGH/CRITICAL** |
| quality | SonarQube | Optional, configurable |
| package | Build image, scan, SBOM | Warn on image vulns |
| sign | Cosign signing | Only on main/tags |
| publish | Artifacts | Only on main/tags |
| deploy | GitOps promotion | Manual for QA/Prod |

## Security Gate Behavior

### SAST (Semgrep)
- **Blocks** on HIGH or CRITICAL findings
- Configurable via `FAIL_ON_HIGH` variable

### SCA (Trivy)
- **Blocks** on CRITICAL vulnerabilities
- Configurable via `FAIL_ON_CRITICAL` variable

### Secrets (Gitleaks)
- **Blocks** on ANY secret detected
- Non-configurable (secrets are always blocking)

## Customization

### Change Thresholds

```yaml
variables:
  FAIL_ON_CRITICAL: "true"
  FAIL_ON_HIGH: "false"  # Relax HIGH threshold
  SEVERITY_THRESHOLD: "CRITICAL"  # Only scan for CRITICAL
```

### Disable Optional Stages

```yaml
quality:sonarqube:
  rules:
    - when: never  # Disable SonarQube
```

### Add Custom Jobs

```yaml
include:
  - project: 'platform/golden-path'
    file: '/ci/gitlab/.gitlab-ci.yml'

# Add custom job
my-custom-test:
  stage: test
  script:
    - ./run-my-tests.sh
```

## Comparison with Jenkins

| Feature | Jenkins | GitLab CI |
|---------|---------|-----------|
| SAST | `securityScan(type: 'sast')` | `security:sast` job |
| SCA | `securityScan(type: 'sca')` | `security:sca` job |
| Secrets | `securityScan(type: 'secrets')` | `security:secrets` job |
| Quality Gate | `qualityGate()` | `quality:sonarqube` job |
| Build Image | `buildImage()` | `package:build-image` job |
| Sign | `signImage()` | `sign:image` job |
| SBOM | `generateSbom()` | `package:sbom` job |
| Promote | `gitopsPromote()` | `deploy:*` jobs |

## Artifacts

All reports are stored as GitLab artifacts:

```
reports/
├── sast-semgrep.json      # SAST findings
├── gl-sast-report.json    # GitLab SAST format
├── sca-trivy.json         # SCA findings
├── secrets-gitleaks.json  # Secrets findings
├── image-scan.json        # Container image scan
├── sbom.json              # CycloneDX SBOM
└── digest.txt             # Image digest
```

## Troubleshooting

### "Docker not available"

Ensure Docker-in-Docker service is configured:

```yaml
services:
  - docker:24-dind
```

### "Permission denied" on GitOps push

Check that `GITOPS_SSH_KEY` is configured as a **File** variable, not a regular variable.

### SonarQube not running

SonarQube is optional. It only runs if `SONAR_TOKEN` is set.

## Migration from Jenkins

1. Copy `.gitlab-ci.yml` to your repository
2. Configure CI/CD variables in GitLab
3. Remove or disable Jenkinsfile
4. Push and verify pipeline runs
5. Compare outputs with previous Jenkins builds

The same scripts are used, so outputs should be identical.
