# OpenShift DevSecOps Golden Path

[![CI](https://github.com/laugiov/openshift-devsecops-golden-path/actions/workflows/ci.yml/badge.svg)](https://github.com/laugiov/openshift-devsecops-golden-path/actions/workflows/ci.yml)
[![Security Scan](https://img.shields.io/badge/security-scanned-green.svg)](https://github.com/laugiov/openshift-devsecops-golden-path/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A battle-tested CI/CD standardization framework for regulated environments. Built from lessons learned deploying pipelines in payment processing, fintech, and healthcare organizations where audit failures cost millions and security incidents end careers.

**This is not a tutorial.** It's a production-grade reference implementation that handles the edge cases most examples ignore.

---

## Executive Summary

**The problem:** Every team builds their own pipeline. Quality varies. Security is inconsistent. Auditors ask questions nobody can answer. Incidents reveal gaps that "should have been caught."

**The solution:** A golden path that teams adopt, not adapt. One way to build, scan, sign, and deploy. Exceptions tracked, not hidden. Evidence generated automatically.

**What this proves:**
- Pipeline standardization at scale (50+ services, same controls)
- Audit-ready evidence generation (PCI-DSS, SOC2)
- Security gates that block, not warn
- Promotion workflow that auditors understand

**Evaluate in 5 minutes:**
```bash
# Clone and run the demo (no Docker required)
git clone <repo-url>
cd openshift-devsecops-golden-path
make demo-e2e
```

**Or manually:**
1. Read this README (2 min)
2. Review [Design Decisions](docs/DESIGN_DECISIONS.md) (3 min)
3. Check [Exception Workflow](security/exceptions/EXCEPTION_WORKFLOW.md) (2 min)
4. Skim the [Jenkins Shared Library](jenkins-shared-library/vars/) (3 min)

---

## Why This Exists

### The Reality of Regulated Environments

In payment/fintech, you don't get to "move fast and break things":

| Requirement | Why It Matters |
|-------------|----------------|
| **Change Control** | PCI-DSS 6.4 requires documented change management |
| **Segregation of Duties** | Developers cannot deploy their own code to production |
| **Audit Trail** | Every deployment must trace back to approved code |
| **Vulnerability Management** | Known vulnerabilities must be tracked and remediated |
| **Evidence** | "Trust me" doesn't work with auditors |

### What Goes Wrong Without Standardization

I've seen these failures repeatedly:

- **Audit finding:** "No evidence that security scans ran before production deployment"
- **Incident:** Vulnerable dependency in production because SCA was "optional"
- **Compliance gap:** 40% of services had no quality gates at all
- **Finger-pointing:** "I thought the other team handled that"

This framework exists because **voluntary best practices don't work** in organizations under regulatory pressure.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           IMMUTABLE BUILD PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   git push ──► Jenkins ──► MANDATORY GATES ──► Signed Artifact             │
│                               │                      │                      │
│                    ┌──────────┴──────────┐          │                      │
│                    ▼          ▼          ▼          ▼                      │
│              ┌─────────┐┌─────────┐┌─────────┐┌─────────┐                  │
│              │  SAST   ││   SCA   ││ Quality ││ Secrets │                  │
│              │ Semgrep ││  Trivy  ││  Sonar  ││Gitleaks │                  │
│              │         ││         ││         ││         │                  │
│              │ BLOCKS  ││ BLOCKS  ││ BLOCKS  ││ BLOCKS  │                  │
│              │ on High ││on Crit. ││on Fail  ││on Find  │                  │
│              └─────────┘└─────────┘└─────────┘└─────────┘                  │
│                                                                             │
│   Artifact = Container Image + SBOM + Signature + Build Provenance         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                              Digest (immutable)
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GITOPS PROMOTION (Argo CD)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────┐              ┌─────────┐                 │
│   │   DEV   │  PR ──► │   QA    │  PR + ──►    │  PROD   │                 │
│   │         │         │         │  Approval    │         │                 │
│   │ auto    │         │ team    │              │ lead +  │                 │
│   │ deploy  │         │ review  │              │ security│                 │
│   └─────────┘         └─────────┘              └─────────┘                 │
│                                                                             │
│   SAME ARTIFACT (by digest) moves through environments                      │
│   Config changes, code doesn't                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Gates block, they don't warn.** A warning is a suggestion. A block is a control.
2. **Artifacts are immutable.** Same SHA256 from build to production.
3. **Promotion is a Git commit.** Auditable, reversible, requires approval.
4. **Exceptions are explicit.** Tracked in Git, time-boxed, require justification.

---

## Compliance Mapping

This framework generates evidence for common compliance requirements:

### PCI-DSS v4.0

| Requirement | Control | Evidence Generated |
|-------------|---------|-------------------|
| **6.2.4** Software development personnel are trained | Enforced via pipeline (can't skip) | Build logs showing gate execution |
| **6.3.1** Security vulnerabilities identified and managed | SCA scan on every build | Trivy reports, vulnerability counts |
| **6.3.2** Custom code reviewed before release | SonarQube quality gate | Quality gate status, PR reviews |
| **6.4.1** Development/test environments separated from production | GitOps env separation | Argo CD sync status per env |
| **6.4.2** Separation of duties between dev and prod | PR approval required for prod | Git commit history, approvers |
| **6.5.x** Common vulnerabilities addressed | SAST scans | Semgrep reports |

### SOC2 Type II

| Trust Criteria | Control | Evidence |
|----------------|---------|----------|
| **CC6.1** Logical access controls | Pipeline RBAC, env separation | Jenkins audit logs, Git history |
| **CC6.6** Security events logged | All pipeline actions logged | Jenkins logs, Argo CD events |
| **CC7.1** Configuration management | GitOps single source of truth | Git history is the audit trail |
| **CC8.1** Change management | PR-based promotion | PR history, approvals |

### Audit Response Cheatsheet

| Auditor Question | Where to Find Evidence |
|------------------|----------------------|
| "How do you ensure only scanned code reaches production?" | Jenkins build logs: every build shows SAST/SCA execution |
| "Who approved this production deployment?" | Git history: PR merge commit shows approver |
| "What vulnerabilities exist in production?" | SBOM + Trivy DB: exact dependency list, can query CVEs |
| "How do you track security exceptions?" | `security/exceptions/`: all exceptions in Git |
| "What changed between these two deployments?" | Git diff between promotion PRs |

---

## Failure Modes and Resilience

A production system must handle failures gracefully. Here's how this framework handles common failure scenarios:

### Build-Time Failures

| Failure | Impact | Mitigation |
|---------|--------|------------|
| **SonarQube down** | Quality gate cannot execute | Pipeline fails fast with clear error. No silent bypass. Ops alerted. |
| **Trivy DB outdated** | SCA may miss recent CVEs | Pipeline checks DB age, warns if >24h old, fails if >72h |
| **Registry unreachable** | Cannot push artifact | Retry with backoff (3x). Fail after. No partial states. |
| **Signing key unavailable** | Cannot sign image | Pipeline fails. Unsigned images cannot promote. |

### Deployment-Time Failures

| Failure | Impact | Mitigation |
|---------|--------|------------|
| **Argo CD down** | No sync to cluster | GitOps state preserved in Git. Manual sync possible. Alert on sync delay >15min. |
| **Deployment fails health check** | Bad version in env | Argo CD auto-rollback to last healthy. Progressive rollout limits blast radius. |
| **Cluster unreachable** | Cannot deploy | Argo CD retries. State preserved. Alert on prolonged disconnect. |

### Recovery Procedures

**Rollback production deployment:**
```bash
# GitOps rollback = revert the PR
git revert <promotion-commit>
git push
# Argo CD syncs previous digest automatically
```

**Emergency hotfix (bypassing normal flow):**
1. Create exception request documenting urgency
2. Get security lead approval (Slack + Git)
3. Use `EMERGENCY=true` flag in pipeline (logs extensively)
4. Post-incident: full postmortem, convert to proper fix

**Pipeline infrastructure down:**
```bash
# Pipeline state is in Git, not Jenkins
# Rebuild Jenkins, reconnect to same repos
# Resume from last successful stage
```

---

## Metrics That Matter

### Platform Health (DORA Metrics)

| Metric | Target | How We Measure |
|--------|--------|----------------|
| **Deployment Frequency** | Daily per service | Count of production promotions |
| **Lead Time for Changes** | <1 day | Commit timestamp → production deploy |
| **Change Failure Rate** | <5% | Rollbacks / total deployments |
| **MTTR** | <1 hour | Incident open → resolved |

### Security Posture

| Metric | Target | How We Measure |
|--------|--------|----------------|
| **Critical vulns in prod** | 0 | Trivy scan of running images |
| **High vulns MTTR** | <7 days | Time from detection to remediation |
| **Exception count** | Trending down | Count of active exceptions |
| **Gate bypass attempts** | 0 | Pipeline logs (should never happen) |

### Adoption

| Metric | Target | How We Measure |
|--------|--------|----------------|
| **Services on golden path** | 100% | Services using shared library / total |
| **Pipeline success rate** | >95% | Successful builds / total builds |
| **Onboarding time** | <1 day | Request → first successful build |

### What We Don't Measure (On Purpose)

- **Lines of code** — Incentivizes bloat
- **Number of deployments** — Without quality context, meaningless
- **Vulnerabilities found** — Finding more isn't better; fixing is

---

## What We Don't Do (And Why)

Strong opinions, loosely held:

### We don't use `latest` tags
**Why:** "Latest" is a lie. It changes. You cannot audit what "latest" meant last Tuesday. Digests are immutable.

### We don't allow self-service production deploys
**Why:** Segregation of duties. The person who wrote the code should not be the same person who approves production deployment. This is non-negotiable in regulated environments.

### We don't do "soft" quality gates
**Why:** A gate that warns but doesn't block is not a gate. It's a suggestion. Suggestions get ignored under deadline pressure.

### We don't allow unsigned images
**Why:** Without signatures, you cannot prove the image in production came from your pipeline. Supply chain attacks exploit this gap.

### We don't store exceptions in ticketing systems
**Why:** Tickets get closed and forgotten. Git history is permanent. When an auditor asks "what exceptions existed on date X?", you can answer with `git log`.

### We don't support "emergency bypass" without tracking
**Why:** Every bypass must be logged, justified, and time-boxed. "Emergency" is not a blank check.

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- make

### 1. Start Local Environment

```bash
git clone <repo-url>
cd openshift-devsecops-golden-path

cp .env.example .env
make up
make health
```

Services:
- **Jenkins** http://localhost:8080 (admin/admin)
- **SonarQube** http://localhost:9000 (admin/admin)
- **Nexus** http://localhost:8081 (admin/admin123)
- **Registry** localhost:5000

### 2. Run Demo Pipeline

```bash
make demo
# Watch at http://localhost:8080/job/demo-service
```

### 3. Verify Controls

```bash
# Verify image signature
cosign verify --key cosign.pub localhost:5000/demo-service:latest

# View SBOM
cat demo-service/sbom.json | jq '.components | length'

# Check quality gate
curl -s http://localhost:9000/api/qualitygates/project_status?projectKey=demo-service
```

---

## Repository Structure

```
├── jenkins-shared-library/     # THE CORE: Reusable pipeline steps
│   ├── vars/                   # goldenPipeline, qualityGate, securityScan...
│   └── src/org/acme/           # Shared classes
├── gitops/                     # Argo CD configuration
│   ├── app-of-apps/            # Bootstrap
│   ├── policies/               # Kubernetes admission policies (Kyverno)
│   └── env/{dev,qa,prod}/      # Environment configs
├── security/                   # Governance
│   ├── policies/               # Security baselines
│   └── exceptions/             # Exception workflow + tracking
├── scripts/                    # Scanner wrappers with adapters
├── docs/                       # Architecture, runbooks
└── demo-service/               # Example application
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md) | Why we made these choices (and what we rejected) |
| [DEMO_RUNBOOK.md](docs/DEMO_RUNBOOK.md) | 7-minute demonstration script |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Technical deep-dive |
| [QUALITY_GATES.md](docs/QUALITY_GATES.md) | Gate configuration and thresholds |
| [ONBOARDING.md](docs/ONBOARDING.md) | Adding a new service (5 minutes) |
| [SECURITY_SETUP.md](docs/SECURITY_SETUP.md) | Jenkins credentials and security configuration |

---

## Extending for Enterprise

### Commercial Scanner Integration

```bash
# Swap Semgrep for Fortify
SAST_ADAPTER=fortify ./scripts/scanners/run-sast.sh

# Swap Trivy for Checkmarx SCA
SCA_ADAPTER=checkmarx ./scripts/scanners/run-sca.sh
```

Adapters normalize output. Pipeline logic doesn't change.

### Multi-Cluster / Multi-Region

The GitOps structure supports multiple clusters:

```
gitops/env/
├── dev/
├── qa/
├── prod-us-east/
├── prod-eu-west/
└── prod-ap-south/
```

Same artifact, region-specific configuration.

### Air-Gapped Environments

For environments without internet access:
- Use keyed Cosign signing (not keyless)
- Mirror Trivy DB internally
- Self-host SonarQube rules

---

## License

MIT License. See [LICENSE](LICENSE).
