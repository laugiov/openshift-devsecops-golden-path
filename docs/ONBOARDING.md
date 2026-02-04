# Service Onboarding Guide

This guide walks you through onboarding a new service to the Golden Path CI/CD platform.

---

## Quick Start (2 minutes)

For teams that want to get started immediately:

```bash
# Create a new service with all configurations
./scripts/bootstrap-service.sh my-service

# Or use interactive mode for guided setup
./scripts/bootstrap-service.sh my-service --interactive
```

The bootstrap script generates:
- Application code with Jenkinsfile and Dockerfile
- Helm chart for Kubernetes deployment
- Environment configurations (dev/qa/prod)
- Argo CD applications for GitOps

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Git access | Push access to the GitOps repository |
| Jenkins access | Ability to view/trigger builds |
| Argo CD access | Read access to view deployments |
| Slack channel | Team channel for build notifications |

### Recommended Knowledge

- Basic Kubernetes concepts (pods, services, deployments)
- Git workflow (branches, PRs)
- How to read container logs

You do **not** need deep expertise in Jenkins, Helm, or Argo CD. The Golden Path abstracts these details.

---

## Option 1: Bootstrap Script (Recommended)

### Basic Usage

```bash
./scripts/bootstrap-service.sh <service-name>
```

Example:
```bash
./scripts/bootstrap-service.sh payment-processor
```

### Interactive Mode

For first-time users, interactive mode asks questions and explains options:

```bash
./scripts/bootstrap-service.sh payment-processor --interactive
```

### Advanced Options

```bash
./scripts/bootstrap-service.sh my-service \
  --port 8080 \
  --team "Platform Team" \
  --email platform@acme.com \
  --description "Handles payment processing" \
  --registry registry.acme.io
```

### Generated Structure

```
services/my-service/
├── Jenkinsfile           # Pipeline configuration
├── Dockerfile            # Container build
├── package.json          # Dependencies
└── src/
    └── index.js          # Application entry point

gitops/
├── apps/my-service/      # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── env/
    ├── dev/values-my-service.yaml
    ├── qa/values-my-service.yaml
    └── prod/values-my-service.yaml

gitops/app-of-apps/templates/
├── my-service-dev.yaml   # Argo CD Application (auto-sync)
├── my-service-qa.yaml    # Argo CD Application (manual)
└── my-service-prod.yaml  # Argo CD Application (approval required)
```

---

## Option 2: Manual Onboarding

If you have an existing application, follow these steps:

### Step 1: Add Jenkinsfile

Create `Jenkinsfile` in your repository root:

```groovy
@Library('golden-path@main') _

goldenPipeline(
    appName: 'my-service',
    buildTool: 'node',

    // Registry configuration
    registry: env.REGISTRY_URL ?: 'registry.acme.io',
    registryCredentialsId: 'registry-credentials',

    // Security scanning - all enabled by default
    enableSast: true,
    enableSca: true,
    enableSecrets: true,
    failOnSecurityFindings: true,

    // Quality gate
    sonarqubeServer: 'SonarQube',
    sonarqubeQualityGate: true,

    // Supply chain security
    enableSbom: true,
    enableSigning: true,
    cosignKeyPath: 'cosign.key',
    cosignPasswordCredentialsId: 'cosign-password',

    // GitOps
    enableGitOps: true,
    gitopsRepo: 'git@github.com:acme/gitops.git',
    gitopsCredentialsId: 'gitops-ssh-key',
    targetEnv: 'dev'
)
```

### Step 2: Create Dockerfile

Ensure your Dockerfile follows security best practices:

```dockerfile
# Use specific version tags
FROM node:20-alpine AS builder

# Run as non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D appuser

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

COPY --chown=appuser:appgroup . .
USER appuser

HEALTHCHECK --interval=30s --timeout=3s \
    CMD wget --spider http://localhost:3000/health || exit 1

EXPOSE 3000
CMD ["node", "src/index.js"]
```

### Step 3: Create Helm Chart

Copy the template and customize:

```bash
cp -r templates/service-template/helm gitops/apps/my-service
# Edit files to replace {{SERVICE_NAME}} placeholders
```

### Step 4: Create Environment Values

Create files in `gitops/env/`:
- `dev/values-my-service.yaml`
- `qa/values-my-service.yaml`
- `prod/values-my-service.yaml`

### Step 5: Register with Argo CD

Create Application manifests in `gitops/app-of-apps/templates/`:
- `my-service-dev.yaml` (auto-sync)
- `my-service-qa.yaml` (manual sync)
- `my-service-prod.yaml` (manual sync + approval)

---

## Configuration Reference

### Jenkinsfile Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `appName` | String | Application name (required) | - |
| `buildTool` | String | 'node', 'maven', 'gradle', 'python' | 'node' |
| `registry` | String | Container registry URL | from env |
| `dockerfile` | String | Dockerfile path | 'Dockerfile' |
| `buildContext` | String | Docker build context | '.' |

### Security Configuration

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `enableSast` | Boolean | Enable SAST scanning | true |
| `enableSca` | Boolean | Enable SCA scanning | true |
| `enableSecrets` | Boolean | Enable secrets detection | true |
| `failOnSecurityFindings` | Boolean | Fail build on findings | true |

### Quality Gate Configuration

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `sonarqubeServer` | String | SonarQube server name | 'SonarQube' |
| `sonarqubeQualityGate` | Boolean | Enable quality gate | true |

### Supply Chain Security

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `enableSbom` | Boolean | Generate SBOM | true |
| `enableSigning` | Boolean | Sign images with Cosign | true |
| `cosignKeyPath` | String | Path to Cosign key | 'cosign.key' |
| `cosignPasswordCredentialsId` | String | Jenkins credential ID for Cosign password | 'cosign-password' |

### GitOps Configuration

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `enableGitOps` | Boolean | Enable GitOps promotion | true |
| `gitopsRepo` | String | GitOps repository URL | '' |
| `targetEnv` | String | Target environment | 'dev' |
| `gitopsCredentialsId` | String | Jenkins credential ID for GitOps SSH key | 'gitops-ssh-key' |

### Credentials Configuration

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `registryCredentialsId` | String | Jenkins credential ID for container registry | 'registry-credentials' |
| `cosignPasswordCredentialsId` | String | Jenkins credential ID for Cosign password | 'cosign-password' |
| `gitopsCredentialsId` | String | Jenkins credential ID for GitOps repository | 'gitops-ssh-key' |

> **Note:** Configure these credentials in Jenkins before running the pipeline. See [Security Setup](SECURITY_SETUP.md) for details.

---

## Promotion Workflow

### DEV → QA

1. Build passes all gates (SAST, SCA, quality gate)
2. Image pushed and signed
3. DEV auto-deploys (auto-sync enabled)
4. Create PR to update QA digest
5. PR requires team review
6. Merge triggers QA deployment

### QA → PROD

1. QA testing complete
2. Create PR to update PROD digest
3. PR requires:
   - Team lead approval
   - Security review (if applicable)
4. Merge triggers PROD deployment

### Rollback

```bash
# Via Argo CD
argocd app rollback my-service-prod <revision>

# Via Git (creates audit trail)
git revert <commit>
git push
```

---

## Troubleshooting

### Build Failures

| Error | Cause | Solution |
|-------|-------|----------|
| SAST failed | High severity findings | Fix findings or request exception |
| SCA failed | Critical vulnerability | Update dependency or request exception |
| Quality Gate failed | Below threshold | Fix issues shown in SonarQube |
| Secrets detected | Hardcoded secrets | Remove and rotate secrets |

### Deployment Issues

| Symptom | Check | Solution |
|---------|-------|----------|
| CrashLoopBackOff | `kubectl logs <pod>` | Fix application error |
| ImagePullBackOff | Registry credentials | Check pull secret |
| Pending | Resource quota | Check namespace quotas |

### Getting Help

1. Check [Runbooks](RUNBOOKS.md) for known issues
2. Review Jenkins build logs
3. Check Argo CD sync status
4. Ask in #platform-support Slack channel

---

## Security Exceptions

If you need to bypass a security gate temporarily:

1. Read [Exception Workflow](../security/exceptions/EXCEPTION_WORKFLOW.md)
2. Create exception request using template
3. Get required approvals
4. Exception is time-boxed (max 90 days)

**Do not** disable security gates without an approved exception.

---

## Best Practices

### Do

- ✅ Use the bootstrap script for new services
- ✅ Keep configurations in Git
- ✅ Use digest-based image references in prod
- ✅ Monitor build notifications
- ✅ Update dependencies regularly

### Don't

- ❌ Skip security scans (use exceptions instead)
- ❌ Deploy to prod without testing in QA
- ❌ Hardcode secrets or credentials
- ❌ Modify pipeline behavior per-service
- ❌ Ignore quality gate failures

---

## FAQ

**Q: Can I use a different programming language?**

A: Yes. Create your own Dockerfile. The pipeline is language-agnostic.

**Q: How do I add a new environment variable?**

A: Update the environment values file:
```yaml
env:
  MY_VAR: "value"
```

**Q: Can I skip the quality gate for urgent fixes?**

A: No. Request an exception if needed. Gates exist to protect production.

**Q: How do I see deployment status?**

A: Check Argo CD:
```bash
argocd app get my-service-dev
```
