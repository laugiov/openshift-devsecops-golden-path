# Design Decisions

This document explains the architectural choices in this project. More importantly, it explains what we tried, what failed, and what we learned.

Good architecture documents show the path taken. Great ones show the paths avoided and why.

---

## Table of Contents

1. [CI/CD Engine: Jenkins](#1-cicd-engine-jenkins)
2. [Pipeline Architecture: Shared Library](#2-pipeline-architecture-shared-library)
3. [GitOps: Helm over Kustomize](#3-gitops-helm-over-kustomize)
4. [Promotion: Immutable Artifacts](#4-promotion-immutable-artifacts)
5. [Quality Gates: Blocking, Not Warning](#5-quality-gates-blocking-not-warning)
6. [Security Scanning: Adapter Pattern](#6-security-scanning-adapter-pattern)
7. [Supply Chain: SBOM + Signing](#7-supply-chain-sbom--signing)
8. [Exception Handling: Git-Tracked](#8-exception-handling-git-tracked)
9. [What We Tried and Abandoned](#9-what-we-tried-and-abandoned)

---

## 1. CI/CD Engine: Jenkins

### The Decision
Jenkins as primary, with GitLab CI and GitHub Actions examples for portability.

### The Real Reason
Every enterprise I've worked with has Jenkins. Not because it's the best tool—it's not—but because:
- It's already there (sunk cost, institutional knowledge)
- Compliance teams have approved it
- Migration risk exceeds migration benefit

**Controversial take:** If you're starting fresh today, don't pick Jenkins. Use GitHub Actions or GitLab CI. But you're probably not starting fresh.

### What We Tried That Failed

**Attempt: Migrate everything to Tekton**

Tekton is technically superior (Kubernetes-native, no master node, better scaling). We tried migrating a 30-service organization.

Result: 6 months in, 4 services migrated, team exhausted, reverted.

Why it failed:
- Learning curve was steeper than expected
- Debugging Tekton pipelines requires K8s expertise most devs don't have
- No good UI for non-experts
- Existing Jenkins plugins had no Tekton equivalent

**Lesson:** The best tool you can't adopt is worse than the good-enough tool you already have.

### Consequences We Accept
- Groovy is painful
- Plugin management is a job
- Jenkins upgrades are scary

---

## 2. Pipeline Architecture: Shared Library

### The Decision
All pipeline logic lives in a shared library. Service repos contain only a thin Jenkinsfile.

### Why This Is Non-Negotiable

I've seen what happens without standardization:

**Horror story #1:** During a security audit, we discovered 47 services. 31 different pipeline configurations. 12 had no security scanning. 8 had scanning but didn't fail on findings. 3 scanned but had "temporarily" disabled the failure for 18 months.

**Horror story #2:** Log4Shell. We needed to know which services were affected. With standardized SBOM generation, answer in 2 hours. Without it? Some teams didn't even know what dependencies they had.

### What We Tried That Failed

**Attempt: Template Jenkinsfiles with copy-paste**

Created a "golden Jenkinsfile" that teams copied into their repos.

Result: 6 months later, 40 different variations. Teams "improved" their copies. No way to push updates centrally.

**Attempt: Let teams opt-in to security scanning**

Made security scanning a parameter teams could enable.

Result: 30% adoption after 1 year. The teams that needed it most were the ones that didn't enable it.

**Lesson:** Opt-in security doesn't work. Make it the default and make opting out painful.

### The Pattern That Works

```groovy
// This is ALL that should be in a service Jenkinsfile
@Library('golden-path@v2.3.1') _

goldenPipeline(
    appName: 'my-service',
    buildTool: 'node'
)
```

The library handles everything. Services don't get to "customize" security.

---

## 3. GitOps: Helm over Kustomize

### The Decision
Helm charts with values files per environment.

### The Honest Assessment

This is a close call. Kustomize has technical merits:
- Native to kubectl
- No templating language
- Simpler mental model

We chose Helm because:
- OpenShift has first-class Helm support
- Enterprise customers expect Helm charts
- Existing ecosystem of charts to build on
- Values files are easier for non-experts to modify

### What We Tried That Failed

**Attempt: Raw manifests with sed replacements**

Early GitOps: YAML files with `__PLACEHOLDER__` values, replaced by `sed` in CI.

Result: One missing escape character broke production. Also, try explaining to an auditor that your deployment process involves `sed`.

**Attempt: Kustomize overlays for everything**

Technically elegant. Patches on patches on patches.

Result: Understanding what actually deploys to production required mentally composing 4 layers of patches. Debugging was painful.

**Lesson:** Choose the tool your team can debug at 3 AM during an incident.

### The Trade-off We Accept
Helm templating is complex. `helm template` output is hard to review. We mitigate with:
- Strict linting (`helm lint`)
- Generated manifests committed to Git for review
- Limited use of complex templating

---

## 4. Promotion: Immutable Artifacts

### The Decision
Artifacts identified by SHA256 digest, never mutable tags.

### Why This Is Absolute

**The incident that made this rule:**

Production was running `myapp:v2.3.1`. Incident reported. Developer says "I'll check what's in v2.3.1." Looks at registry. Finds the image. Debugs for 4 hours. Finally realizes: someone pushed a "fix" to the same tag yesterday. The image in production wasn't the image they were looking at.

Tags are lies. Digests are truth.

### What "Immutable" Actually Means

```yaml
# WRONG - mutable reference
image: registry.example.com/myapp:latest
image: registry.example.com/myapp:v2.3.1

# CORRECT - immutable reference
image: registry.example.com/myapp@sha256:a]3f8c2e1b9d7a6e5c4f3b2a1...
```

The exact same bytes that passed QA are what runs in production. Not "the same version"—the same bits.

### The Inconvenience We Accept
- Digests are ugly and long
- Humans can't remember them
- Tools must resolve tags to digests

Worth it.

---

## 5. Quality Gates: Blocking, Not Warning

### The Decision
Gates that fail the build. No warnings. No "informational" scans.

### The Psychology Behind This

Warnings don't work. I have data:

**Experiment:** Two teams, same codebase, same scanner.
- Team A: Scanner warnings displayed but don't fail build
- Team B: Scanner findings fail the build

After 6 months:
- Team A: 847 open warnings, trending up, "we'll fix them in the refactor"
- Team B: 12 open findings, all with approved exceptions, trending down

**Warnings become noise.** Developers learn to ignore them. The scanner becomes "that thing that always complains."

### What We Tried That Failed

**Attempt: Gradual rollout with warnings first**

Plan: Start with warnings, then convert to failures once teams are "ready."

Result: Teams were never "ready." Warnings accumulated. Converting to failures now meant fixing 200+ issues. Never happened.

**Lesson:** Start strict. It's easier to relax constraints than to tighten them.

### The Hard Line
```
If a gate doesn't fail the build, it's not a gate. It's a suggestion.
We don't do suggestions.
```

---

## 6. Security Scanning: Adapter Pattern

### The Decision
Wrapper scripts with pluggable adapters for different scanners.

### The Business Reality

Every organization has their blessed security tools. Usually:
- Enterprise bought Fortify/Checkmarx licenses 5 years ago
- Security team mandates specific tools
- You can't just use Semgrep because it's better

### The Pattern

```bash
# Interface: run-sast.sh
# - Runs SAST scan
# - Outputs normalized JSON report
# - Exit 0 = pass, Exit 1 = fail

# Implementation selected by environment
SAST_ADAPTER=${SAST_ADAPTER:-semgrep}

case $SAST_ADAPTER in
    semgrep)   source adapters/semgrep-adapter.sh ;;
    fortify)   source adapters/fortify-adapter.sh ;;
    checkmarx) source adapters/checkmarx-adapter.sh ;;
esac
```

### Why Not Direct Integration

**Attempt: Hardcode Fortify in pipeline**

Result: Different client wanted Checkmarx. Required pipeline rewrite. Two months of work.

**With adapters:** New client, different scanner? Write an adapter (2-3 days), pipeline unchanged.

### The Trade-off
Adapters add a layer of abstraction. But that layer is what lets us:
- Demo with open source tools
- Deploy with enterprise tools
- Switch tools without pipeline changes

---

## 7. Supply Chain: SBOM + Signing

### The Decision
CycloneDX SBOM + Cosign signatures for every artifact.

### Why This Became Mandatory

**Log4Shell timeline at one organization:**

- Day 0: CVE announced
- Day 1: "Which services use Log4j?" Nobody knows.
- Day 2: Manual audit begins. Teams check their pom.xml files.
- Day 5: Realize transitive dependencies also matter. Start over.
- Day 14: Finally have a complete list. Start patching.

**With SBOM:**

- Day 0: CVE announced
- Day 0 + 2 hours: Query SBOM database, complete list of affected services
- Day 1: Patches rolling out

### The Signing Decision

SBOM tells you what's in the artifact. Signing tells you the artifact came from your pipeline.

**Without signing:** Attacker compromises registry, replaces image. You deploy malware.

**With signing:** Deployment fails signature verification. Attack detected.

### What We Chose

| Tool | Why |
|------|-----|
| CycloneDX | Best tooling support, JSON format, works with Trivy |
| Cosign (Sigstore) | Keyless option, transparency log, wide adoption |

We specifically avoided:
- SPDX: More complex, legal-focused, less tooling
- Notary v2: Good standard, immature tooling

---

## 8. Exception Handling: Git-Tracked

### The Decision
All exceptions documented in Git with expiration dates.

### Why Not Jira/ServiceNow

**The auditor test:** "Show me all security exceptions that were active on March 15th."

With Jira:
- Search for tickets with certain labels
- Hope the labels were applied consistently
- Export, filter, pray

With Git:
```bash
git log --until="2024-03-15" -- security/exceptions/
```

Done.

### The Cultural Change This Requires

Exceptions in Git means:
- Security reviews exception PRs (extra work)
- Exceptions are visible to everyone (uncomfortable)
- Expired exceptions are obvious (accountability)

Some teams resist this. They prefer exceptions hidden in tickets where nobody looks.

That's exactly why we don't do tickets.

---

## 9. What We Tried and Abandoned

Learning from failure is more valuable than documenting success.

### Abandoned: Per-Service Security Configuration

**The idea:** Let each service configure its own security thresholds.

**Why it failed:** Teams configured lax thresholds. "Our service is internal, we don't need strict scanning." Internal services get compromised too.

**What we do instead:** One configuration, centrally managed. Exceptions require justification.

### Abandoned: Security Dashboard Instead of Gates

**The idea:** Aggregate scan results into a dashboard. Let teams prioritize.

**Why it failed:** Dashboards get ignored. Out of sight, out of mind. After 6 months, thousands of findings, zero fixed.

**What we do instead:** Fail the build. Can't ignore that.

### Abandoned: Gradual Rollout of Controls

**The idea:** Start permissive, gradually tighten.

**Why it failed:** "Gradually" never happened. There was always a reason to delay. Always a deadline. Always a "we'll do it next quarter."

**What we do instead:** Start strict. Day one. Retrofitting security is 10x harder than building it in.

### Abandoned: Letting Teams Choose Their CI Tool

**The idea:** Teams know best. Let them pick Jenkins, GitLab CI, GitHub Actions, whatever.

**Why it failed:** Supporting 4 CI tools means 4x the maintenance. No shared library works across all. Standards drift.

**What we do instead:** One CI tool, well-supported. Freedom within constraints.

### Abandoned: Manual Approval in Pipeline

**The idea:** Pipeline pauses for manual approval before production.

**Why it failed:**
- Approvals became rubber stamps (nobody really reviewed)
- Approvers weren't online when needed (delayed deployments)
- No audit trail of what was reviewed

**What we do instead:** GitOps promotion via PR. Approval is code review. Audit trail is Git history.

---

## Summary of Principles

1. **Make the right thing easy and the wrong thing hard.** Don't rely on discipline; rely on defaults.

2. **Opt-out, not opt-in.** Security controls should require effort to disable, not enable.

3. **Warnings are worthless.** If it matters, fail the build.

4. **Choose debuggability over elegance.** At 3 AM during an incident, you need obvious, not clever.

5. **Standardize aggressively.** Variation is the enemy of security at scale.

6. **Track decisions in code.** If it's not in Git, it doesn't exist for auditors.

7. **Fail fast, fail loud.** Silent failures are the worst kind.

---

## Future Considerations

| Initiative | Status | Rationale |
|------------|--------|-----------|
| SLSA Level 3 | Evaluating | Stronger provenance guarantees |
| Policy-as-Code (OPA) | Planned | Admission control in cluster |
| Multi-cluster GitOps | Designed | Geographic distribution |
| Tekton migration | On hold | Revisit when tooling matures |
