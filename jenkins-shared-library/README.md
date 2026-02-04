# Golden Path Jenkins Shared Library

Opinionated CI/CD pipeline library for regulated environments. All security gates are mandatory and blocking.

## Quick Start

In your service's `Jenkinsfile`:

```groovy
@Library('golden-path@v1.0.0') _

goldenPipeline(
    appName: 'my-service',
    buildTool: 'node'
)
```

That's it. The library handles everything else.

## Configuration in Jenkins

1. Go to **Manage Jenkins** > **Configure System**
2. Find **Global Pipeline Libraries**
3. Add a library:
   - Name: `golden-path`
   - Default version: `main` (or a specific tag like `v1.0.0`)
   - Retrieval method: Modern SCM
   - Source Code Management: Git
   - Project Repository: `<this-repo-url>`
   - Library Path: `jenkins-shared-library`

## Available Pipeline Steps

### Main Entry Point

| Step | Description |
|------|-------------|
| `goldenPipeline` | Complete pipeline with all security gates |

### Security Scanning

| Step | Description |
|------|-------------|
| `securityScan(type: 'sast')` | Static Application Security Testing (Semgrep/Fortify) |
| `securityScan(type: 'sca')` | Software Composition Analysis (Trivy/Grype/Snyk) |
| `securityScan(type: 'secrets')` | Secrets Detection (Gitleaks/TruffleHog) |

### Quality

| Step | Description |
|------|-------------|
| `qualityGate` | SonarQube analysis and quality gate enforcement |

### Container

| Step | Description |
|------|-------------|
| `buildImage` | Build OCI container image |
| `pushImage` | Push image to registry |
| `signImage` | Sign image with Cosign |

### Supply Chain

| Step | Description |
|------|-------------|
| `generateSbom` | Generate CycloneDX SBOM |

### GitOps

| Step | Description |
|------|-------------|
| `gitopsPromote` | Promote artifact via GitOps commit |
| `gitopsPromote.createPR` | Create promotion PR for review |

### Notifications

| Step | Description |
|------|-------------|
| `notifySlack` | Send Slack notification |

## Configuration Options

### goldenPipeline Parameters

```groovy
goldenPipeline(
    // Required
    appName: 'my-service',           // Application name (lowercase, alphanumeric, hyphens)

    // Build
    buildTool: 'node',               // node, maven, gradle, python, go
    dockerfile: 'Dockerfile',
    buildContext: '.',
    buildArgs: [:],

    // Registry
    registry: 'localhost:5000',

    // Security (all enabled by default)
    enableSast: true,
    enableSca: true,
    enableSecrets: true,
    failOnSecurityFindings: true,

    // Quality
    sonarqubeServer: 'SonarQube',
    sonarqubeQualityGate: true,

    // Supply Chain
    enableSbom: true,
    enableSigning: true,
    cosignKeyPath: 'cosign.key',

    // GitOps
    enableGitOps: true,
    gitopsRepo: 'git@github.com:org/gitops.git',
    targetEnv: 'dev',

    // Notifications
    slackChannel: '#builds',

    // Emergency Mode (requires justification)
    emergency: false,
    emergencyJustification: ''
)
```

## Adapter Pattern

Security scanners are pluggable via adapters:

```bash
# Use different SAST scanner
SAST_ADAPTER=fortify ./run-sast.sh

# Use different SCA scanner
SCA_ADAPTER=snyk ./run-sca.sh

# Use different secrets scanner
SECRETS_ADAPTER=trufflehog ./run-secrets-scan.sh
```

Available adapters:

| Type | Adapters |
|------|----------|
| SAST | semgrep (default), fortify, checkmarx |
| SCA | trivy (default), grype, snyk |
| Secrets | gitleaks (default), trufflehog |

## Directory Structure

```
jenkins-shared-library/
├── vars/                    # Global pipeline steps
│   ├── goldenPipeline.groovy
│   ├── securityScan.groovy
│   ├── qualityGate.groovy
│   ├── buildImage.groovy
│   ├── signImage.groovy
│   ├── generateSbom.groovy
│   ├── gitopsPromote.groovy
│   ├── pushImage.groovy
│   └── notifySlack.groovy
├── src/org/acme/            # Shared classes
│   ├── PipelineConfig.groovy
│   ├── SecurityReport.groovy
│   └── BuildInfo.groovy
├── resources/               # Static resources
└── test/                    # Unit tests
```

## Emergency Mode

For critical hotfixes that must bypass normal gates:

```groovy
goldenPipeline(
    appName: 'my-service',
    buildTool: 'node',
    emergency: true,
    emergencyJustification: 'Critical security patch for CVE-2024-XXXX, approved by Security Lead'
)
```

**Warning:** Emergency mode is logged extensively for audit purposes. All bypasses require justification and are subject to post-incident review.

## Extending the Library

### Adding a New Scanner Adapter

1. Create adapter function in `securityScan.groovy`:

```groovy
def runNewScanner(String targetPath, String reportFile) {
    // Implementation
}
```

2. Add to adapter switch statement:

```groovy
case 'new-scanner':
    findings = runNewScanner(targetPath, reportFile)
    break
```

### Adding a New Build Tool

1. Add case in `buildApplication()` in `goldenPipeline.groovy`:

```groovy
case 'rust':
    sh 'cargo build --release'
    sh 'cargo test'
    break
```

2. Update validation in `validateConfig()` to include new tool.

## License

MIT
