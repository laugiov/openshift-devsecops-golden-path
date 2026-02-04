# Security Setup Guide

This guide covers the security configuration required for the Golden Path CI/CD platform.

---

## Prerequisites

Before setting up security controls, ensure you have:

- Jenkins admin access
- Access to container registry credentials
- Access to security scanning tool APIs (SonarQube, etc.)
- Git repository access for GitOps

---

## 1. Jenkins Credentials Setup

### Required Credentials

Configure these credentials in Jenkins at **Manage Jenkins > Credentials**:

| Credential ID | Type | Description | Required For |
|---------------|------|-------------|--------------|
| `registry-credentials` | Username/Password | Container registry authentication | Image push |
| `cosign-password` | Secret text | Cosign private key password | Image signing |
| `gitops-ssh-key` | SSH Username with private key | GitOps repository access | GitOps promotion |
| `sonarqube-token` | Secret text | SonarQube API token | Quality gate |
| `slack-webhook` | Secret text | Slack webhook URL | Notifications |

### Creating Registry Credentials

```bash
# Jenkins CLI example
java -jar jenkins-cli.jar -s http://jenkins:8080/ \
  create-credentials-by-xml system::system::jenkins _ << EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>registry-credentials</id>
  <description>Container registry credentials</description>
  <username>your-registry-user</username>
  <password>your-registry-password</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
```

### Creating Cosign Password Credential

```bash
java -jar jenkins-cli.jar -s http://jenkins:8080/ \
  create-credentials-by-xml system::system::jenkins _ << EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>cosign-password</id>
  <description>Cosign private key password</description>
  <secret>your-cosign-password</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF
```

---

## 2. Cosign Key Management

### Generating Cosign Keys

**Important**: Never store private keys in Git repositories.

```bash
# Generate key pair (will prompt for password)
cosign generate-key-pair

# This creates:
# - cosign.key (private key - keep secret!)
# - cosign.pub (public key - can be shared)
```

### Recommended Key Storage

| Environment | Storage Method |
|-------------|----------------|
| Development | Local file with Jenkins credential |
| Production | HashiCorp Vault or AWS KMS |
| Enterprise | Hardware Security Module (HSM) |

### Using KMS-backed Keys (Recommended for Production)

```bash
# AWS KMS
cosign generate-key-pair --kms awskms:///alias/cosign-key

# HashiCorp Vault
cosign generate-key-pair --kms hashivault://cosign-key

# GCP KMS
cosign generate-key-pair --kms gcpkms://projects/PROJECT/locations/LOCATION/keyRings/KEYRING/cryptoKeys/KEY
```

### Jenkins Integration

Store the Cosign key path and password in Jenkins:

1. Upload `cosign.key` to a secure location on Jenkins agents
2. Create `cosign-password` credential with the key password
3. Reference in Jenkinsfile:

```groovy
goldenPipeline(
    appName: 'my-service',
    cosignKeyPath: '/opt/cosign/cosign.key',  // Absolute path on agent
    cosignPasswordCredentialsId: 'cosign-password'
)
```

---

## 3. SonarQube Configuration

### Create Project Token

1. Log into SonarQube as admin
2. Go to **Administration > Security > Users**
3. Create a token for Jenkins
4. Store as `sonarqube-token` credential in Jenkins

### Configure Quality Gate

1. Go to **Quality Gates** in SonarQube
2. Create or select a quality gate
3. Configure thresholds:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Coverage | < 80% | Fail |
| Duplicated Lines | > 3% | Fail |
| Maintainability Rating | Worse than A | Fail |
| Reliability Rating | Worse than A | Fail |
| Security Rating | Worse than A | Fail |
| Security Hotspots Reviewed | < 100% | Fail |

4. Set as default for new projects

### Jenkins Configuration

Configure SonarQube server in Jenkins:

1. **Manage Jenkins > Configure System**
2. Add SonarQube server:
   - Name: `SonarQube`
   - Server URL: `https://sonarqube.acme.com`
   - Server authentication token: Select `sonarqube-token`

---

## 4. Container Registry Configuration

### Registry Authentication

For private registries, create credentials in Jenkins:

```yaml
# Example for different registries
registries:
  # Docker Hub
  docker.io:
    credentialsId: dockerhub-credentials

  # AWS ECR
  <account>.dkr.ecr.<region>.amazonaws.com:
    credentialsId: ecr-credentials

  # Google GCR
  gcr.io:
    credentialsId: gcr-credentials

  # Azure ACR
  <registry>.azurecr.io:
    credentialsId: acr-credentials

  # Private registry
  registry.acme.io:
    credentialsId: registry-credentials
```

### Insecure Registries (Development Only)

For local development with insecure registries:

```json
// /etc/docker/daemon.json
{
  "insecure-registries": ["localhost:5000"]
}
```

**Warning**: Never use insecure registries in production.

---

## 5. GitOps Repository Access

### SSH Key Setup

1. Generate SSH key pair:

```bash
ssh-keygen -t ed25519 -C "jenkins@acme.com" -f jenkins-gitops
```

2. Add public key to Git repository as deploy key with write access

3. Create Jenkins credential:
   - Type: SSH Username with private key
   - ID: `gitops-ssh-key`
   - Username: `git`
   - Private Key: Contents of `jenkins-gitops`

### Repository Permissions

The GitOps repository should have:

| Branch | Protection | Who Can Push |
|--------|------------|--------------|
| `main` | Protected | Jenkins (via PR merge) |
| `promote/*` | None | Jenkins |

---

## 6. Security Scanning Tools

### SAST - Semgrep (Default)

No additional configuration required. Uses `--config=auto`.

For custom rules:

```yaml
# .semgrep.yaml in service repository
rules:
  - id: custom-rule
    patterns:
      - pattern: eval(...)
    message: "Avoid eval()"
    severity: ERROR
```

### SAST - Fortify (Enterprise)

Required credentials:

| Credential | Description |
|------------|-------------|
| `fortify-token` | Fortify SSC API token |

Environment variables:

```bash
FORTIFY_URL=https://fortify.acme.com
FORTIFY_PROJECT_ID=12345
```

### SAST - Checkmarx (Enterprise)

Required credentials:

| Credential | Description |
|------------|-------------|
| `checkmarx-credentials` | Username/password for Checkmarx |

Environment variables:

```bash
CHECKMARX_URL=https://checkmarx.acme.com
CHECKMARX_PROJECT_NAME=my-project
```

### SCA - Trivy (Default)

No additional configuration required.

For private registries:

```bash
# Set registry credentials
export TRIVY_USERNAME=user
export TRIVY_PASSWORD=pass
```

### SCA - Snyk (Alternative)

Required credentials:

| Credential | Description |
|------------|-------------|
| `snyk-token` | Snyk API token |

### Secrets Detection - Gitleaks (Default)

Custom configuration via `.gitleaks.toml`:

```toml
[allowlist]
paths = [
  '''test/fixtures/.*''',
  '''.*_test\.go'''
]

[[rules]]
description = "Generic API Key"
regex = '''(?i)api[_-]?key[_-]?=\s*['"]?([a-zA-Z0-9]{32,})['"]?'''
```

---

## 7. Kubernetes Image Verification

### Option A: Sigstore Policy Controller

Install policy controller:

```bash
helm repo add sigstore https://sigstore.github.io/helm-charts
helm install policy-controller sigstore/policy-controller \
  --namespace sigstore-system \
  --create-namespace
```

Create ClusterImagePolicy:

```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: require-signed-images
spec:
  images:
    - glob: "registry.acme.io/**"
  authorities:
    - key:
        data: |
          -----BEGIN PUBLIC KEY-----
          <your-cosign-public-key>
          -----END PUBLIC KEY-----
```

### Option B: Kyverno

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        resources:
          kinds:
            - Pod
      verifyImages:
        - imageReferences:
            - "registry.acme.io/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      <your-cosign-public-key>
                      -----END PUBLIC KEY-----
```

---

## 8. Slack Notifications

### Create Webhook

1. Go to Slack App settings
2. Create Incoming Webhook
3. Select channel for notifications
4. Copy webhook URL

### Jenkins Configuration

Store webhook as credential:

- Type: Secret text
- ID: `slack-webhook`
- Value: `https://hooks.slack.com/services/xxx/yyy/zzz`

---

## 9. Verification Checklist

After setup, verify each component:

```bash
# Test registry push
docker login registry.acme.io
docker push registry.acme.io/test:latest

# Test Cosign signing
cosign sign --key cosign.key registry.acme.io/test:latest

# Test SonarQube connectivity
curl -u token: https://sonarqube.acme.com/api/system/health

# Test GitOps repository access
git clone git@github.com:acme/gitops.git

# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test notification"}' \
  https://hooks.slack.com/services/xxx/yyy/zzz
```

---

## 10. Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Registry push fails | Invalid credentials | Verify `registry-credentials` in Jenkins |
| Cosign sign fails | Wrong password | Check `cosign-password` credential |
| Quality gate timeout | SonarQube unreachable | Verify network and `sonarqube-token` |
| GitOps push fails | SSH key not authorized | Add public key as deploy key |
| Slack notification fails | Invalid webhook | Regenerate webhook URL |

### Debugging Credentials

```groovy
// Add to Jenkinsfile for debugging (remove after)
withCredentials([usernamePassword(
    credentialsId: 'registry-credentials',
    usernameVariable: 'U',
    passwordVariable: 'P'
)]) {
    sh 'echo "Username length: ${#U}"'
    sh 'echo "Password length: ${#P}"'
}
```

---

---

## 11. Secrets Rotation Process

Regular rotation of credentials is essential for security. Follow these procedures for each credential type.

### Rotation Schedule

| Credential | Rotation Frequency | Trigger Events |
|------------|-------------------|----------------|
| Registry credentials | 90 days | Employee departure, suspected compromise |
| Cosign key | Annual | Key compromise, algorithm upgrade |
| GitOps SSH key | 90 days | Employee departure |
| SonarQube token | 90 days | Token exposure |
| Slack webhook | Annual | Channel restructure |

### Cosign Key Rotation

**Impact**: All new images will be signed with new key. Old signatures remain valid.

```bash
# 1. Generate new key pair
cosign generate-key-pair --output-key-prefix cosign-v2

# 2. Update Jenkins credential 'cosign-password' with new password

# 3. Deploy new key to Jenkins agents
scp cosign-v2.key jenkins-agent:/opt/cosign/

# 4. Update pipeline config
cosignKeyPath: '/opt/cosign/cosign-v2.key'

# 5. Add new public key to verification policies (keep old key for transition)
# In Kyverno policy, add both keys:
authorities:
  - keys:
      publicKeys: |
        <old-key>
        <new-key>

# 6. After transition period (30 days), remove old key from policies

# 7. Archive old key securely (for verification of old images)
```

### Registry Credentials Rotation

```bash
# 1. Generate new credentials in registry

# 2. Update Jenkins credential
java -jar jenkins-cli.jar update-credentials-by-xml \
  system::system::jenkins _ registry-credentials < new-creds.xml

# 3. Test with manual build
make demo

# 4. Revoke old credentials in registry after verification
```

### GitOps SSH Key Rotation

```bash
# 1. Generate new SSH key
ssh-keygen -t ed25519 -C "jenkins@acme.com" -f jenkins-gitops-v2

# 2. Add new public key to GitOps repo as deploy key

# 3. Update Jenkins credential 'gitops-ssh-key'

# 4. Test GitOps promotion
# Trigger a build and verify promotion works

# 5. Remove old public key from GitOps repo
```

### Emergency Key Compromise

If a key is suspected to be compromised:

1. **Immediately revoke** the compromised credential
2. **Generate new** credentials following rotation procedures
3. **Audit** recent builds for unauthorized access
4. **Notify** security team via `#security-alerts`
5. **Document** the incident in security incident tracker
6. **Review** access logs for anomalies

### Rotation Checklist

Before rotation:
- [ ] Notify team of planned rotation
- [ ] Schedule during low-traffic period
- [ ] Prepare rollback procedure
- [ ] Test in non-production first

During rotation:
- [ ] Create new credential
- [ ] Update Jenkins configuration
- [ ] Test with manual build
- [ ] Monitor for failures

After rotation:
- [ ] Revoke old credential
- [ ] Update documentation
- [ ] Log rotation in change management system

---

## Related Documentation

- [Onboarding Guide](ONBOARDING.md)
- [Security Guardrails](../security/GUARDRAILS.md)
- [Exception Workflow](../security/exceptions/EXCEPTION_WORKFLOW.md)
- [Architecture Overview](ARCHITECTURE.md)
