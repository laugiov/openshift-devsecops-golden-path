# Enterprise Secrets Management

This document describes patterns and best practices for managing secrets in CI/CD pipelines and Kubernetes deployments.

## Principles

1. **Never hardcode secrets** - All secrets must come from secure stores
2. **Least privilege** - Each service gets only the secrets it needs
3. **Audit trail** - All secret access is logged
4. **Rotation** - Secrets should be rotatable without downtime
5. **Environment separation** - Different secrets per environment

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Secret Sources                                │
├──────────────────┬─────────────────┬────────────────────────────────┤
│   HashiCorp      │    External     │      Kubernetes                │
│     Vault        │  Secret Manager │       Secrets                  │
│                  │   (AWS/GCP/Az)  │                                │
└────────┬─────────┴────────┬────────┴───────────────┬────────────────┘
         │                  │                        │
         ▼                  ▼                        ▼
┌────────────────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline (Jenkins/GitLab)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │ Credentials │  │ withVault() │  │ Environment │                │
│  │   Plugin    │  │   step      │  │  Variables  │                │
│  └─────────────┘  └─────────────┘  └─────────────┘                │
└────────────────────────────────────────────────────────────────────┘
         │                  │                        │
         ▼                  ▼                        ▼
┌────────────────────────────────────────────────────────────────────┐
│                    Kubernetes / OpenShift                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │  External   │  │   Sealed    │  │   Native    │                │
│  │   Secrets   │  │   Secrets   │  │   Secrets   │                │
│  │  Operator   │  │             │  │             │                │
│  └─────────────┘  └─────────────┘  └─────────────┘                │
└────────────────────────────────────────────────────────────────────┘
```

## CI/CD Secret Patterns

### Jenkins Credentials

Store secrets in Jenkins Credentials Store:

```groovy
// String credential
withCredentials([string(credentialsId: 'registry-token', variable: 'TOKEN')]) {
    sh "docker login -u user -p ${TOKEN} registry.io"
}

// Username/Password
withCredentials([usernamePassword(
    credentialsId: 'registry-creds',
    usernameVariable: 'USER',
    passwordVariable: 'PASS'
)]) {
    sh "docker login -u ${USER} -p ${PASS} registry.io"
}

// SSH Key
withCredentials([sshUserPrivateKey(
    credentialsId: 'gitops-key',
    keyFileVariable: 'SSH_KEY'
)]) {
    sh "GIT_SSH_COMMAND='ssh -i ${SSH_KEY}' git push"
}

// File credential (e.g., Cosign key)
withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
    sh "cosign sign --key ${COSIGN_KEY} image@sha256:..."
}
```

### Jenkins Vault Integration

For HashiCorp Vault:

```groovy
// Using Vault Plugin
def secrets = [
    [path: 'secret/data/myapp/prod', engineVersion: 2, secretValues: [
        [envVar: 'DB_PASSWORD', vaultKey: 'password'],
        [envVar: 'API_KEY', vaultKey: 'api_key']
    ]]
]

withVault(configuration: [vaultUrl: 'https://vault.example.com'],
          vaultSecrets: secrets) {
    sh './deploy.sh'
}
```

### GitLab CI Variables

Configure in GitLab > Settings > CI/CD > Variables:

```yaml
# .gitlab-ci.yml
deploy:
  script:
    # REGISTRY_PASSWORD is a masked/protected variable
    - docker login -u $REGISTRY_USER -p $REGISTRY_PASSWORD $REGISTRY_URL
    - docker push $IMAGE_NAME

# File variables
sign:
  script:
    # COSIGN_KEY is a File variable
    - cosign sign --key $COSIGN_KEY $IMAGE@$DIGEST
```

## Kubernetes Secret Patterns

### Native Secrets (Basic)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: myapp
type: Opaque
stringData:
  database-url: "postgresql://..."
  api-key: "secret-key"
```

**Note**: Native secrets are base64-encoded, not encrypted. Use for development only.

### Sealed Secrets (GitOps-friendly)

Sealed Secrets encrypt secrets that can be stored in Git:

```bash
# Install kubeseal CLI
brew install kubeseal

# Create sealed secret
kubectl create secret generic app-secrets \
    --from-literal=api-key=secret123 \
    --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml
```

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: app-secrets
  namespace: myapp
spec:
  encryptedData:
    api-key: AgBy8hP...encrypted...
```

### External Secrets Operator

Sync secrets from external stores:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: myapp
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: app-secrets
  data:
    - secretKey: database-url
      remoteRef:
        key: secret/data/myapp/prod
        property: database_url
    - secretKey: api-key
      remoteRef:
        key: secret/data/myapp/prod
        property: api_key
```

### HashiCorp Vault with Kubernetes Auth

```yaml
# ClusterSecretStore for Vault
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "myapp-role"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
```

## Secret Types

### Required Secrets for Golden Path

| Secret | Type | Used By | Storage |
|--------|------|---------|---------|
| Registry credentials | Username/Password | Image push/pull | Jenkins Credentials |
| Cosign private key | File | Image signing | Jenkins File Credential |
| Cosign password | String | Key decryption | Jenkins String Credential |
| GitOps SSH key | SSH Key | Git operations | Jenkins SSH Credential |
| SonarQube token | String | Quality analysis | Jenkins String Credential |
| Fortify token | String | SAST scanning | Jenkins String Credential |
| Checkmarx credentials | Username/Password | SAST scanning | Jenkins Credentials |
| Slack webhook | String | Notifications | Jenkins String Credential |

### Environment-Specific Secrets

| Environment | Secret Store | Rotation | Backup |
|-------------|--------------|----------|--------|
| Development | Kubernetes Secrets | Manual | Git (Sealed) |
| QA | Sealed Secrets | Manual | Git |
| Production | External Secrets + Vault | Automated | Vault HA |

## Best Practices

### 1. Never Log Secrets

```groovy
// BAD - secret may appear in logs
sh "echo ${SECRET}"

// GOOD - use set +x
sh '''
    set +x
    docker login -p "${SECRET}" registry.io
'''
```

### 2. Mask Secrets in CI

```groovy
// Jenkins - secret automatically masked
withCredentials([string(credentialsId: 'token', variable: 'TOKEN')]) {
    // TOKEN is masked in console output
}
```

```yaml
# GitLab - mark variable as "Masked"
# Settings > CI/CD > Variables > [x] Mask variable
```

### 3. Limit Secret Scope

```groovy
// BAD - secret available entire pipeline
environment {
    SECRET = credentials('my-secret')
}

// GOOD - secret available only where needed
stage('Deploy') {
    steps {
        withCredentials([...]) {
            // secret available only here
        }
    }
}
```

### 4. Use Service Accounts

```yaml
# Kubernetes - use service account instead of hardcoded credentials
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  annotations:
    # AWS - IRSA
    eks.amazonaws.com/role-arn: arn:aws:iam::123456:role/myapp-role
    # GCP - Workload Identity
    iam.gke.io/gcp-service-account: myapp@project.iam.gserviceaccount.com
```

### 5. Rotate Secrets Regularly

```bash
# Schedule secret rotation
# Vault - use dynamic secrets with TTL
vault write database/roles/myapp-role \
    db_name=mydb \
    creation_statements="..." \
    default_ttl="1h" \
    max_ttl="24h"
```

## Security Checklist

- [ ] No secrets in source code
- [ ] No secrets in Docker images
- [ ] No secrets in CI/CD logs
- [ ] Secrets are encrypted at rest
- [ ] Secrets are transmitted over TLS
- [ ] Secret access is audited
- [ ] Secrets have expiration/rotation
- [ ] Least privilege access
- [ ] Separate secrets per environment
- [ ] Secrets scanning in pipeline

## Troubleshooting

### "Permission denied" accessing secret

1. Check credential ID spelling
2. Verify Jenkins credential scope (Global vs Folder)
3. Check Kubernetes RBAC for service account

### Secret not rotating

1. Check External Secrets refreshInterval
2. Verify Vault lease renewal
3. Check ESO controller logs

### Secret appearing in logs

1. Enable secret masking in CI
2. Use `set +x` in shell scripts
3. Review echo/print statements
