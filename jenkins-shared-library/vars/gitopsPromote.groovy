#!/usr/bin/env groovy

/**
 * GitOps Promote Step
 *
 * Promotes an artifact through environments using GitOps pattern.
 * Creates a Git commit in the GitOps repository to trigger Argo CD sync.
 *
 * Usage:
 *   gitopsPromote(repo: 'git@github.com:org/gitops.git', app: 'my-service', image: 'registry/app@sha256:...', environment: 'dev')
 */

def call(Map config = [:]) {
    def gitopsRepo = config.repo ?: error("gitopsPromote requires 'repo' parameter")
    def appName = config.app ?: error("gitopsPromote requires 'app' parameter")
    def image = config.image ?: error("gitopsPromote requires 'image' parameter")
    def environment = config.environment ?: 'dev'
    def credentialsId = config.credentialsId ?: 'gitops-credentials'
    def branch = config.branch ?: 'main'
    // Use service-specific values file pattern: values-<app>.yaml
    def valuesFile = config.valuesFile ?: "env/${environment}/values-${appName}.yaml"
    def requireDigest = config.requireDigest != false  // Default: require digest

    echo "=== GitOps Promote ==="
    echo "Application: ${appName}"
    echo "Environment: ${environment}"
    echo "Image: ${image}"
    echo "Repository: ${gitopsRepo}"
    echo "Values file: ${valuesFile}"

    // Validate image reference uses digest for immutability
    if (!image.contains('@sha256:')) {
        if (requireDigest) {
            error "GitOps promotion requires image digest (@sha256:...) for immutability. Got: ${image}"
        } else {
            echo "WARNING: Image reference should use digest (@sha256:...) for immutability"
            echo "Current reference: ${image}"
        }
    }

    // Validate digest format if present
    if (image.contains('@sha256:')) {
        def digestMatch = image =~ /@(sha256:[a-f0-9]{64})$/
        if (!digestMatch) {
            error "Invalid image digest format. Expected sha256:<64 hex chars>, got: ${image}"
        }
    }

    def result = [:]

    // Clone GitOps repo, update values, commit and push
    dir('gitops-repo') {
        // Checkout GitOps repository
        checkout([
            $class: 'GitSCM',
            branches: [[name: "*/${branch}"]],
            userRemoteConfigs: [[
                url: gitopsRepo,
                credentialsId: credentialsId
            ]]
        ])

        // Update values file
        def updated = updateValuesFile(valuesFile, appName, image, config)

        if (updated) {
            // Commit and push
            result = commitAndPush(appName, environment, image, credentialsId)
        } else {
            echo "No changes detected, skipping commit"
            result = [
                status: 'unchanged',
                message: 'Image reference already up to date'
            ]
        }
    }

    // Clean up
    sh 'rm -rf gitops-repo'

    echo "GitOps promotion complete"

    return result
}

/**
 * Update values file with new image reference
 */
def updateValuesFile(String valuesFile, String appName, String image, Map config) {
    if (!fileExists(valuesFile)) {
        echo "Creating new values file: ${valuesFile}"
        sh "mkdir -p \$(dirname ${valuesFile})"
    }

    // Parse image reference
    def imageRef = parseImageReference(image)

    // Determine update strategy based on file type
    if (valuesFile.endsWith('.yaml') || valuesFile.endsWith('.yml')) {
        return updateYamlValues(valuesFile, imageRef, config)
    } else if (valuesFile.endsWith('.json')) {
        return updateJsonValues(valuesFile, imageRef, config)
    } else {
        error "Unsupported values file format: ${valuesFile}"
    }
}

/**
 * Parse image reference into components
 */
def parseImageReference(String image) {
    def parts = [:]

    if (image.contains('@')) {
        // Image with digest: registry/repo@sha256:...
        def atIndex = image.lastIndexOf('@')
        parts.repository = image.substring(0, atIndex)
        parts.digest = image.substring(atIndex + 1)
        parts.tag = ''
    } else if (image.contains(':')) {
        // Image with tag: registry/repo:tag
        def colonIndex = image.lastIndexOf(':')
        parts.repository = image.substring(0, colonIndex)
        parts.tag = image.substring(colonIndex + 1)
        parts.digest = ''
    } else {
        // Image without tag: registry/repo
        parts.repository = image
        parts.tag = 'latest'
        parts.digest = ''
    }

    parts.full = image

    return parts
}

/**
 * Update YAML values file
 */
def updateYamlValues(String valuesFile, Map imageRef, Map config) {
    def imagePath = config.imagePath ?: 'image'
    def repositoryKey = config.repositoryKey ?: 'repository'
    def tagKey = config.tagKey ?: 'tag'
    def digestKey = config.digestKey ?: 'digest'

    // Read current file content
    def currentContent = ''
    if (fileExists(valuesFile)) {
        currentContent = readFile(valuesFile)
    }

    // Use yq to update values if available, otherwise use sed
    def exitCode = sh(
        script: "command -v yq >/dev/null 2>&1",
        returnStatus: true
    )

    if (exitCode == 0) {
        // Use yq for proper YAML manipulation
        if (imageRef.digest) {
            sh """
                yq eval '.${imagePath}.${repositoryKey} = "${imageRef.repository}"' -i ${valuesFile}
                yq eval '.${imagePath}.${digestKey} = "${imageRef.digest}"' -i ${valuesFile}
                yq eval '.${imagePath}.${tagKey} = ""' -i ${valuesFile}
            """
        } else {
            sh """
                yq eval '.${imagePath}.${repositoryKey} = "${imageRef.repository}"' -i ${valuesFile}
                yq eval '.${imagePath}.${tagKey} = "${imageRef.tag}"' -i ${valuesFile}
            """
        }
    } else {
        // Fallback: create/update values file with sed or cat
        def newContent = """
# Generated by Golden Path Pipeline
# Updated: ${new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}
image:
  repository: ${imageRef.repository}
  tag: "${imageRef.tag}"
  digest: "${imageRef.digest}"
"""
        writeFile(file: valuesFile, text: newContent.trim())
    }

    // Check if file actually changed
    def newContent = readFile(valuesFile)
    return currentContent != newContent
}

/**
 * Update JSON values file
 */
def updateJsonValues(String valuesFile, Map imageRef, Map config) {
    def currentContent = fileExists(valuesFile) ? readFile(valuesFile) : '{}'

    def values = readJSON(text: currentContent)

    if (!values.image) {
        values.image = [:]
    }

    values.image.repository = imageRef.repository
    values.image.tag = imageRef.tag
    values.image.digest = imageRef.digest

    def newContent = groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(values))
    writeFile(file: valuesFile, text: newContent)

    return currentContent != newContent
}

/**
 * Commit and push changes
 */
def commitAndPush(String appName, String environment, String image, String credentialsId) {
    def commitMessage = """Promote ${appName} to ${environment}

Image: ${image}
Triggered by: ${env.BUILD_URL ?: 'manual'}
Commit: ${env.GIT_COMMIT ?: 'unknown'}

Automated promotion by Golden Path Pipeline
"""

    sshagent([credentialsId]) {
        sh """
            git config user.email "pipeline@acme.com"
            git config user.name "Golden Path Pipeline"
            git add -A
            git commit -m '${commitMessage.replace("'", "\\'")}' || true
            git push origin HEAD
        """
    }

    // Get commit SHA
    def commitSha = sh(
        script: "git rev-parse HEAD",
        returnStdout: true
    ).trim()

    return [
        status: 'promoted',
        commitSha: commitSha,
        app: appName,
        environment: environment,
        image: image,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Create promotion PR instead of direct commit
 * Use for QA/Prod environments that require review
 */
def createPR(Map config = [:]) {
    def gitopsRepo = config.repo ?: error("createPR requires 'repo' parameter")
    def appName = config.app ?: error("createPR requires 'app' parameter")
    def image = config.image ?: error("createPR requires 'image' parameter")
    def sourceEnv = config.sourceEnvironment ?: 'dev'
    def targetEnv = config.targetEnvironment ?: 'qa'
    def credentialsId = config.credentialsId ?: 'gitops-credentials'
    def baseBranch = config.baseBranch ?: 'main'

    echo "=== Create Promotion PR ==="
    echo "Application: ${appName}"
    echo "From: ${sourceEnv} -> To: ${targetEnv}"
    echo "Image: ${image}"

    def branchName = "promote/${appName}/${targetEnv}/${new Date().format('yyyyMMdd-HHmmss')}"
    def prUrl = ''

    dir('gitops-repo') {
        checkout([
            $class: 'GitSCM',
            branches: [[name: "*/${baseBranch}"]],
            userRemoteConfigs: [[
                url: gitopsRepo,
                credentialsId: credentialsId
            ]]
        ])

        sshagent([credentialsId]) {
            // Create feature branch
            sh "git checkout -b ${branchName}"

            // Update values file (using service-specific pattern)
            def valuesFile = config.valuesFile ?: "env/${targetEnv}/values-${appName}.yaml"
            def imageRef = parseImageReference(image)
            updateYamlValues(valuesFile, imageRef, config)

            // Commit
            def commitMessage = """Promote ${appName} to ${targetEnv}

Image: ${image}
Source environment: ${sourceEnv}
Triggered by: ${env.BUILD_URL ?: 'manual'}
"""

            sh """
                git config user.email "pipeline@acme.com"
                git config user.name "Golden Path Pipeline"
                git add -A
                git commit -m '${commitMessage.replace("'", "\\'")}' || true
                git push origin ${branchName}
            """

            // Create PR using gh CLI if available
            def prBody = """
## Promotion Request

**Application:** ${appName}
**Target Environment:** ${targetEnv}
**Image:** ${image}

### Checklist
- [ ] Security scans passed
- [ ] Quality gate passed
- [ ] SBOM generated
- [ ] Image signed

### Triggered By
Build: ${env.BUILD_URL ?: 'manual'}

---
*Automated promotion by Golden Path Pipeline*
"""

            def ghAvailable = sh(
                script: 'command -v gh >/dev/null 2>&1',
                returnStatus: true
            ) == 0

            if (ghAvailable) {
                prUrl = sh(
                    script: """
                        gh pr create \
                            --title "Promote ${appName} to ${targetEnv}" \
                            --body '${prBody.replace("'", "\\'")}' \
                            --base ${baseBranch} \
                            --head ${branchName} \
                            2>/dev/null || echo ""
                    """,
                    returnStdout: true
                ).trim()
            }
        }
    }

    // Clean up
    sh 'rm -rf gitops-repo'

    return [
        status: 'pr_created',
        branch: branchName,
        prUrl: prUrl,
        app: appName,
        sourceEnvironment: sourceEnv,
        targetEnvironment: targetEnv,
        image: image,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Wait for Argo CD sync after promotion
 */
def waitForSync(Map config = [:]) {
    def appName = config.app ?: error("waitForSync requires 'app' parameter")
    def environment = config.environment ?: 'dev'
    def timeout = config.timeout ?: 5  // minutes
    def argocdServer = config.argocdServer ?: env.ARGOCD_SERVER

    echo "=== Wait for Argo CD Sync ==="
    echo "Application: ${appName}-${environment}"
    echo "Timeout: ${timeout} minutes"

    def appFullName = "${appName}-${environment}"

    timeout(time: timeout, unit: 'MINUTES') {
        def synced = false
        def attempts = 0

        while (!synced && attempts < 30) {
            attempts++

            def status = sh(
                script: """
                    argocd app get ${appFullName} --output json 2>/dev/null | \
                    jq -r '.status.sync.status' || echo "Unknown"
                """,
                returnStdout: true
            ).trim()

            echo "Sync status: ${status} (attempt ${attempts})"

            if (status == 'Synced') {
                synced = true
            } else {
                sleep(10)
            }
        }

        if (!synced) {
            error "Argo CD sync did not complete within ${timeout} minutes"
        }
    }

    echo "Argo CD sync complete"

    return [
        app: appFullName,
        status: 'synced',
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}
