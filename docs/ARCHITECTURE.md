# Architecture Overview

This document provides a technical deep-dive into the Golden Path architecture.

## System Context

```mermaid
flowchart TB
    subgraph DEV["Developer Workflow"]
        A[Developer] -->|git push| B[Service Repository]
    end

    subgraph CI["CI/CD Layer"]
        B -->|webhook| C[Jenkins Pipeline]
        C --> D{Security Gates}
        D -->|SAST| E[Semgrep/Fortify]
        D -->|SCA| F[Trivy/Grype]
        D -->|Secrets| G[Gitleaks]
        D -->|Quality| H[SonarQube]

        E & F & G & H -->|pass| I[Build Image]
        I --> J[Sign with Cosign]
        J --> K[Push to Registry]
        K --> L[Generate SBOM]
    end

    subgraph GITOPS["GitOps Layer"]
        L -->|PR with digest| M[GitOps Repository]
        M -->|sync| N[Argo CD]
    end

    subgraph K8S["Kubernetes / OpenShift"]
        N -->|deploy| O[DEV]
        N -->|deploy| P[QA]
        N -->|deploy| Q[PROD]
    end

    style D fill:#ff6b6b,color:#fff
    style J fill:#4ecdc4,color:#fff
    style N fill:#45b7d1,color:#fff
```

## Pipeline Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as Git Repository
    participant Jenkins as Jenkins
    participant Scan as Security Scanners
    participant Sonar as SonarQube
    participant Reg as Container Registry
    participant GitOps as GitOps Repo
    participant Argo as Argo CD
    participant K8s as Kubernetes

    Dev->>Git: git push
    Git->>Jenkins: webhook trigger

    rect rgb(255, 235, 235)
        Note over Jenkins,Scan: Security Gates (Blocking)
        Jenkins->>Scan: SAST scan
        Jenkins->>Scan: SCA scan
        Jenkins->>Scan: Secrets scan
        Scan-->>Jenkins: results
    end

    Jenkins->>Sonar: code analysis
    Sonar-->>Jenkins: quality gate status

    rect rgb(235, 255, 235)
        Note over Jenkins,Reg: Build & Sign
        Jenkins->>Jenkins: build container image
        Jenkins->>Jenkins: sign with Cosign
        Jenkins->>Reg: push image + signature
        Jenkins->>Jenkins: generate SBOM
        Jenkins->>Reg: attach SBOM attestation
    end

    Jenkins->>GitOps: create PR (image digest)

    rect rgb(235, 235, 255)
        Note over GitOps,K8s: GitOps Promotion
        GitOps->>Argo: PR merged
        Argo->>K8s: sync application
        K8s->>K8s: verify signature
        K8s-->>Argo: deployment complete
    end
```

## Component Details

### Jenkins Shared Library

The shared library provides standardized pipeline steps:

```mermaid
graph LR
    subgraph vars["vars/ - Pipeline Steps"]
        A[goldenPipeline.groovy]
        B[securityScan.groovy]
        C[qualityGate.groovy]
        D[buildImage.groovy]
        E[signImage.groovy]
        F[generateSbom.groovy]
        G[gitopsPromote.groovy]
    end

    subgraph util["Utilities"]
        H[containerUtils.groovy]
        I[notifySlack.groovy]
    end

    A --> B & C & D & E & F & G
    D & E & F --> H
```

```
jenkins-shared-library/
├── vars/                    # Global pipeline functions
│   ├── goldenPipeline.groovy   # Main orchestration
│   ├── qualityGate.groovy      # SonarQube integration
│   ├── securityScan.groovy     # SAST/SCA/DAST orchestration
│   ├── buildImage.groovy       # Container build
│   ├── signImage.groovy        # Cosign signing
│   ├── generateSbom.groovy     # SBOM generation
│   ├── gitopsPromote.groovy    # Environment promotion
│   └── containerUtils.groovy   # Shared utilities
├── src/org/acme/            # Shared classes
└── test/groovy/             # Spock unit tests
```

### GitOps Structure

```mermaid
graph TB
    subgraph gitops["gitops/"]
        subgraph aoa["app-of-apps/"]
            A[Chart.yaml]
            B[templates/]
        end

        subgraph apps["apps/"]
            C[demo-service/]
            D[other-service/]
        end

        subgraph env["env/"]
            E[dev/values-*.yaml]
            F[qa/values-*.yaml]
            G[prod/values-*.yaml]
        end

        subgraph policies["policies/"]
            H[image-verification-policy.yaml]
        end
    end

    B -->|discovers| C & D
    C --> E & F & G
    H -->|enforces signatures| G
```

```
gitops/
├── app-of-apps/             # Bootstrap application
│   └── templates/
│       └── application.yaml    # Discovers all apps
├── apps/                    # Application definitions
│   └── demo-service/
│       ├── Chart.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           └── ingress.yaml
├── env/                     # Environment overrides
│   ├── dev/values-*.yaml
│   ├── qa/values-*.yaml
│   └── prod/values-*.yaml
└── policies/                # Admission policies
    └── image-verification-policy.yaml
```

### Security Scanning Architecture

```mermaid
flowchart LR
    subgraph input["Source Code"]
        A[Application Code]
        B[Dependencies]
        C[Container Image]
    end

    subgraph scanners["Scanners"]
        D[SAST Adapter]
        E[SCA Adapter]
        F[Secrets Adapter]
        G[DAST Adapter]
    end

    subgraph tools["Pluggable Tools"]
        D1[Semgrep]
        D2[Fortify]
        D3[Checkmarx]

        E1[Trivy]
        E2[Grype]
        E3[Snyk]

        F1[Gitleaks]
        F2[TruffleHog]

        G1[OWASP ZAP]
        G2[Nuclei]
    end

    A --> D --> D1 & D2 & D3
    B --> E --> E1 & E2 & E3
    A --> F --> F1 & F2
    C --> G --> G1 & G2
```

## Data Flow

### Build Flow

1. Developer pushes code
2. Jenkins webhook triggers pipeline
3. Pipeline executes stages:
   - Checkout source
   - Build application
   - Run tests
   - Execute security scans (parallel)
   - Check quality gate
   - Build container image
   - Push to registry
   - Sign image with Cosign
   - Generate and attach SBOM

### Deployment Flow

```mermaid
flowchart LR
    A[Pipeline] -->|1. Create PR| B[GitOps Repo]
    B -->|2. Review & Merge| C[PR Merged]
    C -->|3. Webhook| D[Argo CD]
    D -->|4. Detect drift| E{Sync?}
    E -->|yes| F[Apply manifests]
    F -->|5. Verify signature| G[Kyverno]
    G -->|valid| H[Deploy Pod]
    G -->|invalid| I[Block & Alert]
```

## Security Architecture

### Trust Boundaries

```mermaid
flowchart TB
    subgraph trusted["TRUSTED ZONE - Build Infrastructure"]
        J[Jenkins]
        N[Nexus]
        R[Registry]
        S[Signing Key]

        J -->|builds| N
        J -->|pushes| R
        J -->|signs with| S
    end

    subgraph verify["VERIFICATION BOUNDARY"]
        V[Signature Verification]
    end

    subgraph deploy["DEPLOYMENT ZONE - Kubernetes"]
        K[Kyverno Policy]
        P[Production Pods]

        K -->|allows| P
    end

    R -->|image + signature| V
    V -->|verified| K
    V -->|rejected| X[Blocked]

    style trusted fill:#e8f5e9
    style verify fill:#fff3e0
    style deploy fill:#e3f2fd
```

### Artifact Integrity

Every artifact has:

| Attribute | Purpose | Tool |
|-----------|---------|------|
| **Digest** | SHA256 hash for immutability | Container Runtime |
| **Signature** | Cryptographic proof of authenticity | Cosign |
| **SBOM** | Bill of materials for transparency | Syft/CycloneDX |
| **Provenance** | Build metadata for traceability | SLSA |

### Emergency Mode Flow

```mermaid
stateDiagram-v2
    [*] --> NormalMode: Default

    NormalMode --> EmergencyRequest: Critical incident
    EmergencyRequest --> Validation: Submit bypass request

    Validation --> Rejected: Missing justification/approver/ticket
    Validation --> Rejected: Attempting to bypass secrets gate
    Validation --> Approved: Valid request

    Approved --> EmergencyMode: Bypass enabled
    EmergencyMode --> AuditLog: All actions logged
    EmergencyMode --> SecurityAlert: Team notified

    AuditLog --> PostIncident: Deployment complete
    PostIncident --> Review: Mandatory review
    Review --> NormalMode: Return to normal

    Rejected --> NormalMode: Fix and retry
```

## Scalability Considerations

### Jenkins Scaling

```mermaid
graph TB
    subgraph controller["Jenkins Controller"]
        A[Job Orchestration]
        B[Configuration]
    end

    subgraph agents["Dynamic Agents"]
        C[Node.js Agent]
        D[Java Agent]
        E[Security Scanner Agent]
        F[Docker Build Agent]
    end

    A --> C & D & E & F

    subgraph k8s["Kubernetes"]
        G[Pod Autoscaling]
    end

    C & D & E & F --> G
```

- Use Jenkins agents for parallel builds
- Separate agents by workload type
- Consider Kubernetes-based dynamic agents

### Registry Scaling

- Use registry replication for performance
- Implement garbage collection for storage
- Consider geo-distributed registries

### GitOps Scaling

- One Argo CD per cluster (or hub-spoke)
- ApplicationSets for multi-cluster
- Progressive sync for large deployments

## Monitoring & Observability

```mermaid
graph LR
    subgraph sources["Data Sources"]
        A[Jenkins Logs]
        B[Argo CD Events]
        C[Kubernetes Metrics]
        D[Security Scan Results]
    end

    subgraph collect["Collection"]
        E[Prometheus]
        F[Loki]
    end

    subgraph visualize["Visualization"]
        G[Grafana Dashboards]
    end

    subgraph alert["Alerting"]
        H[AlertManager]
        I[Slack/PagerDuty]
    end

    A & B & C & D --> E & F
    E & F --> G
    E --> H --> I
```

### Key Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Deployment Frequency | Daily | < 1/week |
| Lead Time | < 1 day | > 3 days |
| Change Failure Rate | < 5% | > 10% |
| MTTR | < 1 hour | > 4 hours |
| Critical Vulns in Prod | 0 | > 0 |
