# XL Release Integration

This document describes the integration points for Digital.ai Release (XL Release) with the Golden Path DevSecOps pipeline.

## Overview

XL Release provides enterprise release orchestration, enabling organizations to manage complex release processes across multiple environments and tools.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Release Orchestration Flow                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌───────────┐     ┌───────────┐     ┌───────────┐     ┌─────────┐ │
│  │  Jenkins  │────▶│ XL Release│────▶│  ArgoCD   │────▶│  Prod   │ │
│  │   Build   │     │  Gate     │     │   Sync    │     │  Env    │ │
│  └───────────┘     └───────────┘     └───────────┘     └─────────┘ │
│        │                 │                 │                 │      │
│        ▼                 ▼                 ▼                 ▼      │
│  ┌───────────┐     ┌───────────┐     ┌───────────┐     ┌─────────┐ │
│  │  Artifact │     │  Approval │     │  Deploy   │     │ Monitor │ │
│  │  Created  │     │  Workflow │     │  Verify   │     │  Alert  │ │
│  └───────────┘     └───────────┘     └───────────┘     └─────────┘ │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Use Cases

### 1. Production Release Gates

XL Release manages approval workflows before production deployments:

- Security review sign-off
- Change Advisory Board (CAB) approval
- Business stakeholder approval
- Compliance verification

### 2. Multi-Environment Orchestration

Coordinate deployments across multiple clusters/regions:

- Blue/Green deployments
- Canary releases
- Regional rollouts
- Rollback coordination

### 3. Release Calendar

Track and schedule releases:

- Planned release windows
- Blackout periods
- Dependency tracking
- Resource allocation

## Integration Architecture

### Jenkins to XL Release

```groovy
// Jenkinsfile - Trigger XL Release
stage('Release Gate') {
    when {
        branch 'main'
    }
    steps {
        script {
            // Create release in XL Release
            def release = xlrCreateRelease(
                serverCredentials: 'xlr-credentials',
                template: 'Golden Path/Production Release',
                releaseTitle: "${APP_NAME}-${VERSION}",
                variables: [
                    [propertyName: 'appName', propertyValue: APP_NAME],
                    [propertyName: 'version', propertyValue: VERSION],
                    [propertyName: 'imageDigest', propertyValue: IMAGE_DIGEST],
                    [propertyName: 'securityScanPassed', propertyValue: SECURITY_PASSED],
                    [propertyName: 'jenkinsJobUrl', propertyValue: BUILD_URL]
                ]
            )

            // Start the release
            xlrStartRelease(
                serverCredentials: 'xlr-credentials',
                releaseId: release.id
            )
        }
    }
}
```

### XL Release to ArgoCD

XL Release tasks can trigger ArgoCD sync:

```yaml
# XL Release task configuration
- task:
    type: argocd.SyncApplication
    application: demo-service-prod
    server: https://argocd.example.com
    syncOptions:
      - Prune=true
      - ApplyOutOfSyncOnly=true
```

## XL Release Templates

### Production Release Template

```yaml
# xl-release-template.yaml
apiVersion: xl-release/v1
kind: Template
metadata:
  name: Golden Path Production Release
spec:
  phases:
    - name: Pre-Deployment Checks
      tasks:
        - name: Verify Security Scan Results
          type: xlrelease.GateTask
          conditions:
            - name: SAST Passed
              type: xlrelease.GateCondition
            - name: Container Scan Passed
              type: xlrelease.GateCondition
            - name: DAST Passed
              type: xlrelease.GateCondition

        - name: Verify Image Signature
          type: script.HttpRequest
          url: "${COSIGN_VERIFY_URL}"
          method: POST

    - name: Approvals
      tasks:
        - name: Security Team Approval
          type: xlrelease.UserInputTask
          owner: security-team
          variables:
            - securityApproved

        - name: CAB Approval
          type: xlrelease.UserInputTask
          owner: change-advisory-board
          conditions:
            - name: Change Ticket Created
              type: xlrelease.GateCondition

    - name: Deployment
      tasks:
        - name: Create GitOps PR
          type: github.CreatePullRequest
          repository: acme/gitops-config
          base: main
          head: "release/${releaseId}"
          title: "Release ${appName} v${version}"

        - name: Sync ArgoCD
          type: argocd.SyncApplication
          application: "${appName}-prod"
          waitForSync: true
          timeout: 600

        - name: Verify Deployment
          type: kubernetes.WaitForDeployment
          namespace: "${appName}-prod"
          deployment: "${appName}"
          timeout: 300

    - name: Post-Deployment
      tasks:
        - name: Run Smoke Tests
          type: script.HttpRequest
          url: "${smokeTestUrl}"

        - name: Update CMDB
          type: servicenow.UpdateCI
          ciSysId: "${cmdbCiId}"
          version: "${version}"

        - name: Notify Stakeholders
          type: slack.PostMessage
          channel: releases
          message: "✅ ${appName} v${version} deployed to production"
```

### Rollback Template

```yaml
apiVersion: xl-release/v1
kind: Template
metadata:
  name: Emergency Rollback
spec:
  phases:
    - name: Rollback
      tasks:
        - name: Confirm Rollback
          type: xlrelease.UserInputTask
          owner: on-call-engineer
          description: "Confirm rollback of ${appName} to version ${previousVersion}"

        - name: Revert GitOps
          type: argocd.SyncApplication
          application: "${appName}-prod"
          revision: "${previousGitCommit}"

        - name: Verify Rollback
          type: kubernetes.WaitForDeployment
          namespace: "${appName}-prod"

        - name: Create Incident
          type: pagerduty.CreateIncident
          title: "Rollback: ${appName}"
          urgency: high
```

## API Integration

### Create Release via API

```bash
# Create a new release from template
curl -X POST "https://xlrelease.example.com/api/v1/templates/Applications/Golden%20Path/Production%20Release/create" \
  -H "Authorization: Bearer ${XLR_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "releaseTitle": "myapp-1.2.3",
    "variables": {
      "appName": "myapp",
      "version": "1.2.3",
      "imageDigest": "sha256:abc123..."
    },
    "autoStart": true
  }'
```

### Query Release Status

```bash
# Get release status
curl "https://xlrelease.example.com/api/v1/releases/${RELEASE_ID}" \
  -H "Authorization: Bearer ${XLR_TOKEN}"
```

## Jenkins Integration Plugin

### Installation

```groovy
// In Jenkins configuration
@Library('xl-release-plugin') _
```

### Usage

```groovy
// Create and start release
def release = xlrCreateRelease(
    serverCredentials: 'xlr-credentials',
    template: 'Golden Path/Production Release',
    releaseTitle: "myapp-${env.VERSION}",
    startRelease: true,
    variables: [
        [propertyName: 'appName', propertyValue: 'myapp'],
        [propertyName: 'version', propertyValue: env.VERSION]
    ]
)

// Wait for release phase completion
xlrWaitForReleasePhase(
    serverCredentials: 'xlr-credentials',
    releaseId: release.id,
    phase: 'Approvals',
    timeout: 3600
)
```

## GitLab CI Integration

```yaml
# .gitlab-ci.yml
create_release:
  stage: release
  image: curlimages/curl:latest
  script:
    - |
      curl -X POST "https://xlrelease.example.com/api/v1/templates/Applications/Golden%20Path/Production%20Release/create" \
        -H "Authorization: Bearer ${XLR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
          \"releaseTitle\": \"${CI_PROJECT_NAME}-${CI_COMMIT_TAG}\",
          \"variables\": {
            \"appName\": \"${CI_PROJECT_NAME}\",
            \"version\": \"${CI_COMMIT_TAG}\",
            \"gitlabPipelineUrl\": \"${CI_PIPELINE_URL}\"
          },
          \"autoStart\": true
        }"
  rules:
    - if: $CI_COMMIT_TAG
```

## Security Considerations

### Credentials Management

- Store XL Release credentials in Jenkins Credentials Store
- Use service accounts with minimal permissions
- Rotate API tokens regularly

### Audit Trail

XL Release provides complete audit logging:
- Who approved releases
- When approvals occurred
- What changes were made
- Deployment timestamps

### RBAC

Configure role-based access:
- **Release Admins**: Create/modify templates
- **Release Managers**: Start releases, approve gates
- **Developers**: View releases, trigger builds
- **Viewers**: Read-only access

## Troubleshooting

### Release Stuck in Gate

1. Check gate conditions in XL Release UI
2. Verify variable values
3. Review task logs

### Integration Timeout

1. Check network connectivity
2. Verify API endpoint availability
3. Increase timeout values

### Approval Not Received

1. Check email/Slack notifications
2. Verify team assignments
3. Review approval workflow

## References

- [Digital.ai Release Documentation](https://docs.digital.ai/release/)
- [XL Release Jenkins Plugin](https://plugins.jenkins.io/xlrelease-plugin/)
- [API Reference](https://docs.digital.ai/release/api/)
