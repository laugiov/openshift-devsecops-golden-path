# Kubernetes Security Policies

This directory contains Kubernetes admission control policies for enforcing security controls at deployment time.

## Overview

These policies ensure that the security controls enforced during CI/CD are also enforced at deployment time:

| Policy | Purpose | Tool |
|--------|---------|------|
| Image Signature Verification | Ensures only signed images are deployed | Kyverno or Sigstore Policy Controller |
| Digest Requirement | Blocks mutable tags (`:latest`) in production | Kyverno |
| SBOM Attestation | Verifies SBOM attestation exists | Sigstore Policy Controller |

## Prerequisites

### Option A: Kyverno (Recommended)

```bash
# Add Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3
```

### Option B: Sigstore Policy Controller

```bash
# Add Helm repository
helm repo add sigstore https://sigstore.github.io/helm-charts
helm repo update

# Install Policy Controller
helm install policy-controller sigstore/policy-controller \
  --namespace sigstore-system \
  --create-namespace
```

## Deploying Policies

### 1. Create Public Key ConfigMap

First, create a ConfigMap with your Cosign public key:

```bash
kubectl create configmap cosign-pubkey \
  --from-file=cosign.pub \
  -n kyverno
```

### 2. Update Policy with Your Key

Edit `image-verification-policy.yaml` and replace the placeholder public key with your actual Cosign public key:

```bash
# Get your public key content
cat cosign.pub

# Edit the policy
# Replace "-----BEGIN PUBLIC KEY-----..." with actual key
```

### 3. Apply the Policy

```bash
kubectl apply -f image-verification-policy.yaml
```

### 4. Verify Policy is Active

```bash
# For Kyverno
kubectl get clusterpolicy verify-image-signatures

# For Sigstore
kubectl get clusterimagepolicy signed-images-policy
```

## Testing

### Test with Unsigned Image

```bash
# This should be BLOCKED
kubectl run test-unsigned \
  --image=registry.acme.io/test:unsigned \
  -n demo-prod

# Expected: Error from admission webhook
```

### Test with Signed Image

```bash
# This should SUCCEED
kubectl run test-signed \
  --image=registry.acme.io/test@sha256:abc123... \
  -n demo-prod
```

## Policy Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `Enforce` | Block non-compliant resources | Production |
| `Audit` | Log but allow | Testing policies |

To switch to audit mode:

```yaml
spec:
  validationFailureAction: Audit  # instead of Enforce
```

## Namespaces

Policies are applied based on namespace patterns:

| Pattern | Mode | Description |
|---------|------|-------------|
| `*-prod`, `production` | Enforce | Production namespaces |
| `*-qa`, `staging` | Enforce | QA/Staging namespaces |
| `*-dev` | Audit | Development (warning only) |

## Troubleshooting

### Check Policy Reports

```bash
# Kyverno
kubectl get policyreport -A

# View details
kubectl describe policyreport -n <namespace>
```

### Debug Admission Webhook

```bash
# Check webhook configuration
kubectl get validatingwebhookconfigurations

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| All pods blocked | Wrong public key | Verify key matches signing key |
| Policy not enforcing | Wrong namespace selector | Check namespace labels |
| Timeout errors | Webhook slow | Increase `webhookTimeoutSeconds` |

## Related Documentation

- [Security Setup Guide](../../docs/SECURITY_SETUP.md)
- [Security Guardrails](../../security/GUARDRAILS.md)
- [Cosign Documentation](https://docs.sigstore.dev/cosign/)
- [Kyverno Documentation](https://kyverno.io/docs/)
