# OpenShift Deployment Guide

This directory contains OpenShift-specific configurations and guidance for deploying Golden Path services on OpenShift/OKD.

## OpenShift vs Kubernetes

OpenShift adds security and operational constraints that require specific attention:

| Feature | Kubernetes | OpenShift |
|---------|------------|-----------|
| Ingress | Ingress resource | **Route** (preferred) or Ingress |
| Security | Pod Security Standards | **SecurityContextConstraints (SCC)** |
| User/Group | Any UID | **Arbitrary UID** (restricted SCC) |
| Registry | External pull | **Internal registry** + ImageStreams |
| Builds | External CI | **BuildConfig** (optional) |

## Quick Start

### Deploy to OpenShift

```bash
# Login to cluster
oc login --token=<token> --server=https://api.cluster.example.com:6443

# Create project (namespace)
oc new-project demo-service

# Apply OpenShift-specific configs
oc apply -k gitops/openshift/overlays/dev/

# Or with Helm
helm upgrade --install demo-service gitops/apps/demo-service \
  -f gitops/openshift/values-openshift.yaml \
  -n demo-service
```

## Security Context Constraints (SCC)

OpenShift uses SCCs instead of Pod Security Standards. Our deployment is compatible with the `restricted` SCC (most secure).

### Required Settings for `restricted` SCC

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        # DO NOT set runAsUser - OpenShift assigns arbitrary UID
```

### Verify SCC Assignment

```bash
# Check which SCC is used
oc get pod <pod-name> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Should return: restricted-v2 (or restricted)
```

## Routes vs Ingress

OpenShift Routes provide native ingress with automatic TLS.

### Route Example

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: demo-service
spec:
  to:
    kind: Service
    name: demo-service
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

### Using Ingress (if required)

OpenShift supports Ingress, but Routes are preferred:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-service
  annotations:
    # OpenShift will create a Route from this Ingress
    route.openshift.io/termination: edge
spec:
  rules:
    - host: demo-service.apps.cluster.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo-service
                port:
                  name: http
```

## Image Pull from External Registry

### Option 1: Create Pull Secret

```bash
oc create secret docker-registry registry-credentials \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=password

# Link to default service account
oc secrets link default registry-credentials --for=pull
```

### Option 2: Use OpenShift Internal Registry

```bash
# Push to internal registry
oc registry login
docker tag demo-service:latest default-route-openshift-image-registry.apps.cluster.example.com/demo-service/demo-service:latest
docker push default-route-openshift-image-registry.apps.cluster.example.com/demo-service/demo-service:latest
```

## Helm Values for OpenShift

Use the `values-openshift.yaml` override:

```yaml
# values-openshift.yaml
openshift:
  enabled: true

# Route instead of Ingress
ingress:
  enabled: false

route:
  enabled: true
  tls:
    termination: edge

# OpenShift-compatible security context
podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  # No runAsUser - OpenShift assigns UID
```

## Local Development with OpenShift

### Option 1: OpenShift Local (CRC)

```bash
# Download from https://developers.redhat.com/products/openshift-local/overview
crc setup
crc start

# Login
eval $(crc oc-env)
oc login -u developer -p developer https://api.crc.testing:6443
```

### Option 2: OpenShift Sandbox (Free)

1. Go to https://developers.redhat.com/developer-sandbox
2. Create free account
3. Get login command from web console

### Option 3: OKD (Community OpenShift)

```bash
# Use Kind with OKD
# Note: Limited SCC support in Kind
```

## Image Signature Verification on OpenShift

OpenShift can verify Cosign signatures using Signature Verification Policy:

```yaml
apiVersion: config.openshift.io/v1
kind: Image
metadata:
  name: cluster
spec:
  registrySources:
    allowedRegistries:
      - registry.example.com
    containerRuntimeSearchRegistries:
      - registry.example.com
---
# Machine Config for signature verification
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 50-signature-verification
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/containers/registries.d/registry-example.yaml
          contents:
            source: data:text/plain;base64,<base64-encoded-config>
```

Or use Kyverno (recommended, cluster-agnostic):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        resources:
          kinds: [Pod]
      verifyImages:
        - image: "registry.example.com/*"
          key: |-
            -----BEGIN PUBLIC KEY-----
            ...
            -----END PUBLIC KEY-----
```

## Namespace/Project Setup

```bash
# Create project with labels
oc new-project demo-service \
  --display-name="Demo Service" \
  --description="Golden Path demo service"

# Add labels for policy targeting
oc label namespace demo-service \
  environment=dev \
  app.kubernetes.io/managed-by=golden-path
```

## Troubleshooting

### "Error creating: pods is forbidden: unable to validate against any security context constraint"

The deployment doesn't meet SCC requirements. Check:

```bash
# See what SCC allows
oc describe scc restricted

# Common fixes:
# - Remove runAsUser (let OpenShift assign)
# - Add runAsNonRoot: true
# - Remove privileged: true
# - Drop all capabilities
```

### "ImagePullBackOff" with internal registry

```bash
# Check service account has pull rights
oc get sa default -o yaml

# Add image pull secret
oc secrets link default <secret-name> --for=pull
```

### Route not accessible

```bash
# Check route status
oc get route demo-service -o yaml

# Check router logs
oc logs -n openshift-ingress deployment/router-default
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `values-openshift.yaml` | Helm values override for OpenShift |
| `base/` | Kustomize base with OpenShift resources |
| `overlays/` | Environment-specific overlays |
| `scc/` | Custom SCC examples (if needed) |
