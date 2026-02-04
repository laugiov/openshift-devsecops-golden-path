# Operational Runbooks

Standard operating procedures for the Golden Path CI/CD platform.

---

## Table of Contents

1. [Pipeline Issues](#pipeline-issues)
2. [Deployment Issues](#deployment-issues)
3. [Security Incidents](#security-incidents)
4. [Infrastructure Recovery](#infrastructure-recovery)
5. [Emergency Procedures](#emergency-procedures)

---

## Pipeline Issues

### RB-001: Build Failing - SAST Gate

**Symptoms:**
- Build fails at "Security Scan" stage
- Error message: "SAST gate failed: X high severity findings"

**Diagnosis:**
```bash
# Check the security report in Jenkins
# Navigate to: Jenkins → Build → Security Reports → SAST

# Or via CLI:
curl -s http://jenkins:8080/job/<job>/lastBuild/artifact/reports/sast-report.json | jq '.findings[] | select(.severity == "HIGH")'
```

**Resolution:**

1. **Fix the findings** (preferred):
   ```
   Review each finding in the SAST report
   Fix the vulnerable code pattern
   Re-run the pipeline
   ```

2. **Request exception** (if fix not immediately possible):
   ```
   Create security exception request
   Get approval from Security Lead
   Add to .semgrepignore with comment referencing exception ID
   Exception must be time-boxed (max 90 days)
   ```

**Prevention:**
- Enable IDE linters with security rules
- Review security findings during PR review
- Run `make security-scan` locally before push

---

### RB-002: Build Failing - SCA Gate

**Symptoms:**
- Build fails at "Dependency Scan" stage
- Error message: "Critical vulnerability found in dependency X"

**Diagnosis:**
```bash
# Check Trivy report
cat reports/trivy-report.json | jq '.Results[].Vulnerabilities[] | select(.Severity == "CRITICAL")'

# Or via Jenkins UI:
# Jenkins → Build → Security Reports → SCA
```

**Resolution:**

1. **Update the dependency** (preferred):
   ```bash
   # Check for fixed version
   npm outdated <package>

   # Update to fixed version
   npm update <package>

   # Or for major version bump
   npm install <package>@latest
   ```

2. **If no fix available**:
   ```
   Check if vulnerability is exploitable in your context
   Create exception request with justification
   Add to .trivyignore with exception reference
   Set remediation timeline
   ```

**Prevention:**
- Enable Dependabot/Renovate for automated updates
- Run `make dependency-check` weekly
- Subscribe to security advisories for critical dependencies

---

### RB-003: Build Failing - Quality Gate

**Symptoms:**
- Build fails at "Quality Gate" stage
- SonarQube shows failed conditions

**Diagnosis:**
```bash
# Check SonarQube dashboard
open http://sonarqube:9000/dashboard?id=<project>

# Via API:
curl -s "http://sonarqube:9000/api/qualitygates/project_status?projectKey=<project>" | jq
```

**Common failure reasons:**
- Coverage below threshold (default: 80%)
- Code duplication above threshold
- New bugs or vulnerabilities introduced
- Security hotspots not reviewed

**Resolution:**

1. **Coverage too low**:
   ```
   Write tests for uncovered code
   Focus on new code coverage first
   Check which files need coverage
   ```

2. **Code duplication**:
   ```
   Extract common code to shared functions
   Review similar patterns and consolidate
   ```

3. **Bugs/vulnerabilities**:
   ```
   Review and fix each issue in SonarQube
   Mark false positives with justification
   ```

**Prevention:**
- Run `make sonar-scan` locally before push
- Check coverage during development
- Review SonarQube feedback on PRs

---

### RB-004: Build Failing - Secrets Detection

**Symptoms:**
- Build fails at "Secrets Scan" stage
- Gitleaks found hardcoded secrets

**Diagnosis:**
```bash
# Check Gitleaks report
cat reports/gitleaks-report.json | jq '.[] | {file: .File, line: .StartLine, rule: .RuleID}'
```

**Resolution:**

1. **If secrets are real and committed**:
   ```
   CRITICAL: Rotate the secret immediately!

   1. Rotate credentials in secret manager
   2. Update service configurations
   3. Contact Security team
   4. Follow incident response procedure
   ```

2. **If false positive**:
   ```
   Add pattern to .gitleaks.toml allowlist
   Include comment explaining why it's safe
   ```

**Prevention:**
- Use pre-commit hooks with Gitleaks
- Store secrets in vault/secret manager
- Never commit credentials

---

### RB-005: Image Signing Failure

**Symptoms:**
- Build fails at "Sign Image" stage
- Cosign errors

**Diagnosis:**
```bash
# Check Cosign key availability
docker exec jenkins ls -la /cosign-keys/

# Check key permissions
docker exec jenkins cat /cosign-keys/cosign.key 2>&1 | head -1
```

**Resolution:**

1. **Key not found**:
   ```bash
   # Generate new key pair
   cosign generate-key-pair

   # Store in appropriate location
   cp cosign.key /path/to/cosign-keys/
   ```

2. **Permission denied**:
   ```bash
   # Fix permissions
   chmod 600 /path/to/cosign-keys/cosign.key
   ```

3. **Registry unreachable**:
   ```bash
   # Check registry connectivity
   curl -v http://registry:5000/v2/
   ```

**Prevention:**
- Monitor key expiration
- Use hardware security modules in production
- Test signing in CI before release

---

## Deployment Issues

### RB-010: Argo CD Sync Failed

**Symptoms:**
- Application stuck in "OutOfSync" state
- Sync operation failed

**Diagnosis:**
```bash
# Check application status
argocd app get <app-name>

# Check sync history
argocd app history <app-name>

# Check Kubernetes events
kubectl -n <namespace> get events --sort-by='.lastTimestamp'
```

**Resolution:**

1. **Manifest error**:
   ```
   Check Argo CD error message
   Fix YAML syntax or resource definition
   Commit and push fix
   ```

2. **Resource conflict**:
   ```
   Check for existing resources with same name
   Remove or rename conflicting resources
   ```

3. **Permission denied**:
   ```
   Check RBAC for Argo CD service account
   Add missing permissions
   ```

**Recovery:**
```bash
# Force sync with prune
argocd app sync <app-name> --prune

# Hard refresh
argocd app refresh <app-name> --hard
```

---

### RB-011: Pod CrashLoopBackOff

**Symptoms:**
- Pod repeatedly crashing
- Status: CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod logs
kubectl -n <namespace> logs <pod-name> --previous

# Check events
kubectl -n <namespace> describe pod <pod-name>

# Check resource usage
kubectl -n <namespace> top pod <pod-name>
```

**Common causes and solutions:**

1. **Application error**:
   ```
   Review logs for stack trace
   Fix application bug
   Redeploy
   ```

2. **Missing configuration**:
   ```
   Check required environment variables
   Verify ConfigMaps and Secrets exist
   ```

3. **Resource limits**:
   ```
   Pod OOMKilled → increase memory limit
   Check actual usage vs limits
   ```

4. **Readiness/liveness probe failure**:
   ```
   Verify health endpoint is accessible
   Check probe configuration (path, port, timing)
   Increase initialDelaySeconds if app needs more startup time
   ```

---

### RB-012: ImagePullBackOff

**Symptoms:**
- Pod stuck in ImagePullBackOff
- Cannot pull container image

**Diagnosis:**
```bash
# Check pod events
kubectl -n <namespace> describe pod <pod-name> | grep -A 10 Events

# Verify image exists
curl -s http://registry:5000/v2/<image>/tags/list
```

**Resolution:**

1. **Image doesn't exist**:
   ```
   Verify correct image tag/digest
   Rebuild and push image
   ```

2. **Registry credentials missing**:
   ```bash
   # Create pull secret
   kubectl create secret docker-registry regcred \
     --docker-server=registry:5000 \
     --docker-username=user \
     --docker-password=pass

   # Reference in deployment or service account
   ```

3. **Network connectivity**:
   ```
   Check if nodes can reach registry
   Verify DNS resolution
   Check firewall rules
   ```

---

### RB-013: Rollback Procedure

**When to rollback:**
- New deployment causing errors
- Performance degradation
- Unexpected behavior in production

**Via Argo CD (preferred):**
```bash
# View history
argocd app history <app-name>

# Rollback to specific revision
argocd app rollback <app-name> <revision>

# Verify rollback
argocd app get <app-name>
```

**Via Git (creates audit trail):**
```bash
# Find commit to revert
git log --oneline gitops/env/prod/values-<service>.yaml

# Revert the commit
git revert <commit-sha>

# Push (triggers sync)
git push
```

**Via Helm (direct, emergency only):**
```bash
# List releases
helm -n <namespace> list

# Rollback
helm -n <namespace> rollback <release> <revision>
```

---

## Security Incidents

### RB-020: Compromised Credentials

**Severity:** CRITICAL

**Immediate Actions:**
```
1. Rotate the compromised credential IMMEDIATELY
2. Notify Security team
3. Check access logs for unauthorized usage
4. Document timeline and scope
```

**Investigation:**
```bash
# Check git history for exposure
git log -p --all -S 'secret_value'

# Check pipeline logs
# Review who had access
# Check for lateral movement
```

**Remediation:**
```
1. Complete credential rotation
2. Update all dependent services
3. Review and harden secret management
4. Add to incident report
5. Lessons learned session
```

---

### RB-021: Vulnerability in Production

**Severity:** HIGH if exploitable

**Assessment:**
```
1. Is the vulnerability exploitable in our context?
2. Is the affected component exposed?
3. What's the blast radius?
```

**Response:**
```
If immediately exploitable:
  1. Enable WAF rules if available
  2. Apply workaround/mitigation
  3. Expedite patch deployment

If not immediately exploitable:
  1. Create exception request
  2. Schedule remediation
  3. Track in vulnerability management
```

---

## Infrastructure Recovery

### RB-030: Jenkins Recovery

**Symptoms:**
- Jenkins unreachable
- Jobs not running

**Quick Recovery:**
```bash
# Restart Jenkins
docker-compose restart jenkins

# Check logs
docker-compose logs -f jenkins

# Verify plugins
docker exec jenkins ls /var/jenkins_home/plugins/
```

**Full Recovery:**
```bash
# If data corrupted, restore from backup
docker-compose down -v
docker volume rm golden-path_jenkins_home

# Restore backup
docker run --rm -v golden-path_jenkins_home:/data -v $(pwd)/backups:/backup \
  alpine tar xzf /backup/jenkins_home.tar.gz -C /data

docker-compose up -d jenkins
```

---

### RB-031: Argo CD Recovery

**Symptoms:**
- Argo CD UI unreachable
- Applications not syncing

**Recovery:**
```bash
# Check Argo CD pods
kubectl -n argocd get pods

# Restart if needed
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout restart statefulset argocd-application-controller

# Reset admin password if locked out
kubectl -n argocd patch secret argocd-secret \
  -p '{"data": {"admin.password": null, "admin.passwordMtime": null}}'
```

---

### RB-032: Kind Cluster Recovery

**Symptoms:**
- Cluster unreachable
- Nodes not ready

**Quick Fix:**
```bash
# Check cluster status
kind get clusters
kubectl get nodes

# Restart cluster (preserves data)
docker restart golden-path-control-plane
docker restart golden-path-worker
docker restart golden-path-worker2
```

**Full Recreation:**
```bash
# Delete and recreate
kind delete cluster --name golden-path
kind create cluster --config kind-config.yaml

# Reinstall components
kubectl apply -k gitops/bootstrap/
```

---

## Emergency Procedures

### EP-001: Production Outage

**Priority:** P0

**Immediate Actions:**
1. Page on-call
2. Open incident bridge
3. Identify impact scope
4. Enable fallback if available

**Communication Template:**
```
[INCIDENT] Service: <name>
Status: Investigating/Identified/Monitoring/Resolved
Impact: <description>
Next Update: <time>
```

### EP-002: Emergency Deployment

**When:** Critical security patch needed

```bash
# Fast-track deployment (still goes through gates)
# 1. Create hotfix branch
git checkout -b hotfix/critical-fix

# 2. Apply fix
# 3. Push and create PR (mark as URGENT)
git push -u origin hotfix/critical-fix

# 4. Get expedited review (Security Lead)
# 5. Merge and monitor
```

**Emergency bypass (requires CTO approval):**
```bash
# Direct deployment (breaks audit trail - document thoroughly)
kubectl -n <namespace> set image deployment/<name> <container>=<image>

# MUST follow up with proper pipeline deployment
```

---

## Appendix: Useful Commands

```bash
# Pipeline
make build               # Trigger build
make logs-jenkins        # View Jenkins logs

# Deployment
make deploy-dev          # Deploy to dev
argocd app sync <app>    # Sync application

# Debugging
kubectl logs -f <pod>    # Stream logs
kubectl exec -it <pod> -- sh  # Shell into pod

# Monitoring
kubectl top pods         # Resource usage
kubectl get events       # Cluster events
```
