# Demo Runbook (7 Minutes)

This guide walks through a demonstration of the Golden Path capabilities.
---

## Prerequisites

Before the demo:

```bash
# Full bootstrap (first time setup)
make bootstrap

# Or if already set up:
make up
make health

# Verify all services are green
make urls
```

### Three Testing Levels

| Level | Command | What It Does |
|-------|---------|--------------|
| 1 | `make demo-level1` | CI infrastructure (Jenkins, SonarQube, Nexus, Registry) |
| 2 | `make demo-level2` | Full pipeline with security scans + SBOM |
| 3 | `make demo-level3` | GitOps with Kind cluster + Argo CD |

For a complete demo:
```bash
make demo-full  # Runs all 3 levels
```

---

## Demo Flow

| Section | Duration | Focus |
|---------|----------|-------|
| 1. Overview | 1 min | README + Architecture |
| 2. Shared Library | 1 min | Reusable pipeline steps |
| 3. Pipeline Run | 2 min | Quality gates in action |
| 4. Supply Chain | 1 min | SBOM + signature |
| 5. GitOps Promotion | 1 min | Environment progression |
| 6. Exception Workflow | 1 min | Governance process |

---

## Section 1: Overview (1 minute)

**Goal:** Establish context and value proposition.

### Script

> "This repository demonstrates a production-ready CI/CD standardization framework for regulated environments. Let me show you the key components."

### Actions

1. Open `README.md` in browser/IDE
2. Scroll to architecture diagram
3. Highlight:
   - Pipeline flow (build → scan → publish → sign)
   - GitOps promotion (dev → qa → prod)
   - Immutable artifacts (digest-based)

### Key Points

- "Every build goes through the same quality gates"
- "Promotion is via Git PR, not manual deployment"
- "Full audit trail for compliance"

---

## Section 2: Shared Library (1 minute)

**Goal:** Show standardization mechanism.

### Script

> "The heart of this is the Jenkins Shared Library. Services include it and get a complete, secure pipeline with one line."

### Actions

1. Navigate to `jenkins-shared-library/vars/`
2. Open `goldenPipeline.groovy`
3. Show the high-level structure

```groovy
// Point out the stages
def call(Map config) {
    pipeline {
        stages {
            stage('Build')     { /* ... */ }
            stage('Test')      { /* ... */ }
            stage('Scan')      { /* ... */ }  // Security scans
            stage('Quality')   { /* ... */ }  // SonarQube gate
            stage('Publish')   { /* ... */ }
            stage('Sign')      { /* ... */ }  // Cosign
            stage('SBOM')      { /* ... */ }  // CycloneDX
        }
    }
}
```

4. Show a service Jenkinsfile:

```groovy
@Library('golden-path') _

goldenPipeline(
    appName: 'my-service',
    buildTool: 'node',
    qualityGate: true,
    securityScan: true
)
```

### Key Points

- "One line to get a complete, compliant pipeline"
- "Central updates without touching each repo"
- "Versioned library with semantic versioning"

---

## Section 3: Pipeline Run (2 minutes)

**Goal:** Show quality gates blocking bad code.

### Actions

1. Open Jenkins: http://localhost:8080
2. Navigate to `demo-service` job
3. Click "Build Now"

While building, explain each stage:

```
┌─────────────────────────────────────────────────────────────┐
│ Stage           │ What happens                              │
├─────────────────────────────────────────────────────────────┤
│ Checkout        │ Clone repo, verify branch                 │
│ Build           │ npm install, compile                      │
│ Test            │ npm test, generate coverage               │
│ Lint            │ ESLint, code style                        │
│ SAST            │ Semgrep scan for security issues          │
│ SCA             │ Trivy scan for vulnerable dependencies    │
│ Secrets         │ Gitleaks scan for leaked credentials      │
│ Quality Gate    │ SonarQube analysis + gate check           │
│ Build Image     │ Docker build with digest                  │
│ Publish         │ Push to Nexus + Registry                  │
│ Sign            │ Cosign signature                          │
│ Generate SBOM   │ CycloneDX bill of materials               │
└─────────────────────────────────────────────────────────────┘
```

### Show a Failed Gate (Optional)

If time permits, show what happens when a gate fails:

1. Introduce a known vulnerability or quality issue
2. Run pipeline
3. Show the blocking stage
4. Explain: "The build cannot proceed until this is fixed"

### Key Points

- "Every stage must pass before proceeding"
- "Security scans run on every build, not just releases"
- "Failed gates block promotion automatically"

---

## Section 4: Supply Chain Security (1 minute)

**Goal:** Demonstrate SBOM and image signing.

### Actions

1. Show SBOM output:

```bash
# View generated SBOM
cat demo-service/sbom.json | jq '.components | length'
# Output: 142 (number of dependencies)

cat demo-service/sbom.json | jq '.components[0]'
# Output: First component with name, version, purl
```

2. Verify image signature:

```bash
# Verify the signed image
cosign verify \
  --key cosign.pub \
  localhost:5000/demo-service:latest

# Output: Verified OK
# Shows: signature, digest, timestamp
```

3. Show attestation:

```bash
# Verify SBOM attestation attached to image
cosign verify-attestation \
  --key cosign.pub \
  --type cyclonedx \
  localhost:5000/demo-service:latest
```

### Key Points

- "SBOM lists every dependency for vulnerability tracking"
- "Image signature proves build integrity"
- "Attestation links SBOM to specific image"

---

## Section 5: GitOps Promotion (1 minute)

**Goal:** Show controlled environment progression.

### Actions

1. Navigate to `gitops/env/` structure:

```
gitops/env/
├── dev/values.yaml       # Auto-deploy
├── qa/values.yaml        # PR required
└── prod/values.yaml      # PR + approval required
```

2. Show a promotion PR:

```yaml
# gitops/env/qa/values.yaml
image:
  repository: registry.example.com/demo-service
  # OLD:
  # digest: sha256:abc123...
  # NEW (in PR):
  digest: sha256:def456...
```

3. Explain the flow:

```
Pipeline completes
       │
       ▼
Creates PR to env/qa/values.yaml
       │
       ▼
Team reviews PR (sees what changed)
       │
       ▼
Merge triggers Argo CD sync
       │
       ▼
QA environment updated with exact artifact
```

### Key Points

- "Promotion is a Git commit, fully auditable"
- "Same artifact (by digest) moves between environments"
- "No manual kubectl/oc commands"

---

## Section 6: Exception Workflow (1 minute)

**Goal:** Show governance for bypassing gates.

### Actions

1. Navigate to `security/exceptions/`

2. Show the workflow document:

```markdown
# EXCEPTION_WORKFLOW.md

## When to Request an Exception
- Critical business deadline
- False positive requiring investigation
- Legacy system awaiting remediation

## Process
1. Create exception request (use template)
2. Document: risk, mitigation, expiration
3. Submit PR to security/exceptions/
4. Security team reviews and approves
5. Exception merged with expiration date
```

3. Show an example exception:

```markdown
# EXC-001-legacy-tls.md

## Summary
Legacy payment gateway requires TLS 1.1

## Risk
Medium - encrypted but outdated protocol

## Mitigation
- Network isolation
- Additional monitoring
- Vendor upgrade in progress

## Expiration
2024-06-30

## Approver
@security-lead - 2024-01-15
```

### Key Points

- "Exceptions are explicit, not hidden"
- "Time-boxed with mandatory expiration"
- "Full audit trail in Git history"

---

## Closing (30 seconds)

### Script

> "This framework provides a standardized, secure path for all services. Teams get compliant pipelines immediately. Security gets visibility and control. Auditors get evidence. Any questions?"

### Summary Slide

| Capability | Benefit |
|------------|---------|
| Shared Library | Consistency across all services |
| Quality Gates | Automatic enforcement |
| SBOM + Signing | Supply chain compliance |
| GitOps | Auditable promotions |
| Exceptions | Governance without blocking |

---

## Troubleshooting

### Jenkins not starting

```bash
make down
make up
docker logs jenkins
```

### SonarQube quality gate not found

```bash
# Ensure SonarQube is initialized
curl http://localhost:9000/api/system/status
# Should return: {"status":"UP"}
```

### Cosign verification fails

```bash
# Regenerate keys
./scripts/signing/generate-cosign-keys.sh
```

### Pipeline times out

Check Docker resources (CPU, memory). Recommended: 4GB+ RAM for full stack.

---

## Customizing the Demo

### Shorter Demo (3 minutes)

Focus on:
1. README architecture (30s)
2. Pipeline run - just show stages (1.5min)
3. SBOM/signing verification (1min)

### Longer Demo (15 minutes)

Add:
- Live coding: add a vulnerability, watch it fail
- SonarQube dashboard walkthrough
- Argo CD UI demonstration
- Nexus artifact browser

---

## Argo CD Demo (Level 3)

### Setup

```bash
# Start Kind cluster with Argo CD
make setup-kind

# Wait for all pods to be ready (may take 2-3 minutes)
kubectl get pods -n argocd --watch
```

### Access Argo CD UI

```bash
# Terminal 1: Start port forward
make argocd-ui

# Terminal 2: Get password
make argocd-password
```

Open https://localhost:8443 and login:
- Username: `admin`
- Password: (from `make argocd-password`)

### Deploy to Environments

```bash
# Push image to local registry
make push

# Deploy to dev
make deploy-dev

# Watch sync in Argo CD UI
make argocd-apps
```

### Demo Script

> "Now let me show you the GitOps side. We have a Kind cluster running locally with Argo CD. When I push an image and update the manifest..."

1. Show Argo CD UI with applications
2. Make a change (update image tag)
3. Watch Argo CD detect and sync
4. Show the application health status

### Cleanup

```bash
# Delete Kind cluster when done
make teardown-kind
```

---

## Full Pipeline Simulation

For demonstrating the complete CI/CD flow without Jenkins:

```bash
# Simulate CI pipeline
make pipeline-ci

# This runs:
# 1. Unit tests
# 2. SAST scan (Semgrep)
# 3. Secrets scan (Gitleaks)
# 4. Container build
# 5. SCA scan (Trivy)
# 6. SBOM generation

# Simulate CD pipeline
make pipeline-cd

# This runs:
# 1. Push to registry
# 2. Sign with Cosign
# 3. Verify signature

# Or run both together
make pipeline-full
```

---

## Quick Reference

### Essential Commands

| Command | Purpose |
|---------|---------|
| `make help` | Show all available commands |
| `make bootstrap` | First-time setup |
| `make up` | Start CI stack |
| `make down` | Stop CI stack |
| `make health` | Check service health |
| `make urls` | Show service URLs |
| `make build` | Build demo-service image |
| `make scan-all` | Run all security scans |
| `make setup-kind` | Create Kind cluster |
| `make teardown-kind` | Delete Kind cluster |
| `make demo-full` | Run complete demo |

### Service URLs

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Jenkins | http://localhost:8080 | admin / admin |
| SonarQube | http://localhost:9000 | admin / admin |
| Nexus | http://localhost:8081 | admin / admin123 |
| Registry | http://localhost:5000 | (no auth) |
| Argo CD | https://localhost:8443 | admin / (see `make argocd-password`) |
