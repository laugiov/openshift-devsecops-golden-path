# Policy-as-Code with Kyverno

This document describes the policy-as-code implementation using Kyverno for Kubernetes/OpenShift clusters.

## Overview

Kyverno is a policy engine designed for Kubernetes that validates, mutates, and generates configurations based on policies defined as Kubernetes resources.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Policy Categories                            │
├─────────────────────┬─────────────────────┬─────────────────────────┤
│   Pod Security      │   Best Practices    │   Supply Chain          │
│   Standards         │                     │   Security              │
├─────────────────────┼─────────────────────┼─────────────────────────┤
│ • Privileged        │ • Required labels   │ • Image signatures      │
│ • Privilege escal.  │ • Resource limits   │ • Registry whitelist    │
│ • Run as non-root   │ • Health probes     │ • Block :latest tag     │
│ • Host namespaces   │ • PDB requirement   │ • Require digest refs   │
│ • Host paths        │ • Default namespace │ • SBOM attestation      │
│ • Capabilities      │ • NodePort services │                         │
│ • Seccomp profiles  │ • Read-only FS      │                         │
└─────────────────────┴─────────────────────┴─────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Kyverno Policy Controller                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │  Validate   │  │   Mutate    │  │  Generate   │                 │
│  │             │  │             │  │             │                 │
│  │ Block/Audit │  │ Auto-fix    │  │ Auto-create │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Installation

### Kyverno

```bash
# Add Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3 \
  --set resources.limits.memory=512Mi

# Verify installation
kubectl get pods -n kyverno
```

### Apply Policies

```bash
# Apply all policies
kubectl apply -f gitops/policies/kyverno/

# Or apply individually
kubectl apply -f gitops/policies/kyverno/baseline-policies.yaml
kubectl apply -f gitops/policies/kyverno/best-practices.yaml
kubectl apply -f gitops/policies/image-verification-policy.yaml
```

## Policy Categories

### Pod Security Standards (Baseline)

These policies implement Kubernetes Pod Security Standards at the baseline level:

| Policy | Action | Description |
|--------|--------|-------------|
| `disallow-privileged-containers` | Enforce | Block privileged mode |
| `disallow-privilege-escalation` | Enforce | Block privilege escalation |
| `disallow-host-namespaces` | Enforce | Block hostPID, hostIPC, hostNetwork |
| `disallow-host-path` | Enforce | Block hostPath volumes |
| `disallow-host-ports` | Enforce | Block hostPort usage |
| `require-drop-cap-net-raw` | Enforce | Require dropping NET_RAW |

### Pod Security Standards (Restricted)

Additional policies for restricted environments:

| Policy | Action | Description |
|--------|--------|-------------|
| `require-run-as-nonroot` | Enforce | Require non-root user |
| `disallow-capabilities` | Enforce | Only allow NET_BIND_SERVICE |
| `restrict-seccomp-profiles` | Enforce | Require RuntimeDefault/Localhost |
| `require-read-only-root-filesystem` | Audit | Recommend read-only root FS |

### Best Practices

Operational excellence policies:

| Policy | Action | Description |
|--------|--------|-------------|
| `require-labels` | Enforce | Require standard K8s labels |
| `require-resource-limits` | Enforce | Require CPU/memory limits |
| `require-probes` | Audit | Recommend health probes in prod |
| `disallow-default-namespace` | Enforce | Block deployments to default NS |
| `disallow-nodeport-services` | Audit | Discourage NodePort services |
| `require-pod-disruption-budget` | Audit | Recommend PDB for prod |

### Supply Chain Security

Image and registry policies:

| Policy | Action | Description |
|--------|--------|-------------|
| `verify-image-signatures` | Enforce | Require Cosign signatures |
| `block-latest-tag` | Enforce | Block :latest in production |
| `require-digest` | Enforce | Require @sha256: references |
| `restrict-image-registries` | Enforce | Whitelist approved registries |

## Validation Actions

### Enforce vs Audit

- **Enforce**: Blocks non-compliant resources from being created
- **Audit**: Allows creation but generates policy violations for reporting

```yaml
spec:
  validationFailureAction: Enforce  # or Audit
```

### Viewing Policy Violations

```bash
# List all policy reports
kubectl get policyreport -A

# View detailed violations
kubectl describe policyreport -n <namespace>

# Get violation count by policy
kubectl get clusterpolicyreport -o jsonpath='{range .items[*]}{.metadata.name}: {.summary.fail}{"\n"}{end}'
```

## Testing Policies

### Test with Dry-Run

```bash
# Test if a pod would be accepted
kubectl apply -f pod.yaml --dry-run=server
```

### Kyverno CLI

```bash
# Install Kyverno CLI
brew install kyverno

# Test policies against resources
kyverno apply policies/ --resource pod.yaml

# Generate policy report
kyverno apply policies/ --resource pod.yaml -o json
```

### Example: Compliant Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/managed-by: argocd
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: registry.acme.io/myapp@sha256:abc123...
      securityContext:
        allowPrivilegeEscalation: false
        privileged: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
            - NET_RAW
      resources:
        limits:
          cpu: "500m"
          memory: "256Mi"
        requests:
          cpu: "100m"
          memory: "128Mi"
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
      readinessProbe:
        httpGet:
          path: /ready
          port: 8080
```

## Environment-Specific Configuration

### Development (Audit Mode)

```yaml
# kustomization.yaml for dev
patches:
  - patch: |-
      - op: replace
        path: /spec/validationFailureAction
        value: Audit
    target:
      kind: ClusterPolicy
```

### Production (Enforce Mode)

```yaml
# kustomization.yaml for prod
patches:
  - patch: |-
      - op: replace
        path: /spec/validationFailureAction
        value: Enforce
    target:
      kind: ClusterPolicy
```

## Exclusions

### Namespace Exclusions

```yaml
spec:
  rules:
    - name: my-rule
      match:
        any:
          - resources:
              kinds:
                - Pod
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kyverno
```

### Specific Resource Exclusions

```yaml
metadata:
  annotations:
    policies.kyverno.io/exclude: "true"
```

## Monitoring

### Prometheus Metrics

Kyverno exposes metrics at `/metrics`:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kyverno
  namespace: kyverno
spec:
  endpoints:
    - port: metrics
  selector:
    matchLabels:
      app.kubernetes.io/name: kyverno
```

### Key Metrics

| Metric | Description |
|--------|-------------|
| `kyverno_policy_results_total` | Total policy evaluations |
| `kyverno_admission_requests_total` | Admission webhook requests |
| `kyverno_policy_rule_results_total` | Results by rule |

## Troubleshooting

### Policy Not Enforcing

1. Check policy status:
   ```bash
   kubectl get clusterpolicy <policy-name> -o yaml
   ```

2. Verify webhook configuration:
   ```bash
   kubectl get validatingwebhookconfigurations
   ```

3. Check Kyverno logs:
   ```bash
   kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
   ```

### Resource Blocked Unexpectedly

1. Get detailed error from dry-run:
   ```bash
   kubectl apply -f resource.yaml --dry-run=server -v=6
   ```

2. Test with Kyverno CLI:
   ```bash
   kyverno apply policies/ --resource resource.yaml --detailed-results
   ```

## References

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Kyverno Policy Library](https://kyverno.io/policies/)
- [Golden Path Pipeline Integration](./PIPELINE_OVERVIEW.md)
