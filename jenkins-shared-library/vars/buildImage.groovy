#!/usr/bin/env groovy

/**
 * Build Container Image Step
 *
 * Builds OCI-compliant container images with proper tagging.
 * Supports both Docker and Podman.
 *
 * Usage:
 *   buildImage(name: 'myapp', tag: 'v1.0.0')
 *   buildImage(name: 'registry/myapp', tag: 'abc123', dockerfile: 'Dockerfile.prod')
 */

def call(Map config = [:]) {
    def imageName = config.name ?: error("buildImage requires 'name' parameter")
    def imageTag = config.tag ?: env.GIT_COMMIT?.take(8) ?: 'latest'
    def dockerfile = config.dockerfile ?: 'Dockerfile'
    def context = config.context ?: '.'
    def buildArgs = config.buildArgs ?: [:]
    def labels = config.labels ?: [:]
    def noCache = config.noCache ?: false
    def platform = config.platform ?: ''  // e.g., 'linux/amd64'

    def fullImageRef = "${imageName}:${imageTag}"

    echo "=== Build Image: ${fullImageRef} ==="
    echo "Dockerfile: ${dockerfile}"
    echo "Context: ${context}"

    // Validate Dockerfile exists
    if (!fileExists(dockerfile)) {
        error "Dockerfile not found: ${dockerfile}"
    }

    // Detect container runtime (use shared utility)
    def runtime = containerUtils.detectRuntime()
    echo "Container runtime: ${runtime}"

    // Build arguments string
    def buildArgsStr = buildArgs.collect { k, v ->
        "--build-arg ${k}=${v}"
    }.join(' ')

    // Standard labels for traceability
    def standardLabels = [
        'org.opencontainers.image.created': new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        'org.opencontainers.image.revision': env.GIT_COMMIT ?: 'unknown',
        'org.opencontainers.image.source': env.GIT_URL ?: 'unknown',
        'org.opencontainers.image.version': imageTag,
        'com.acme.pipeline.build-number': env.BUILD_NUMBER ?: 'unknown',
        'com.acme.pipeline.job-name': env.JOB_NAME ?: 'unknown'
    ]

    // Merge custom labels
    def allLabels = standardLabels + labels
    def labelsStr = allLabels.collect { k, v ->
        "--label \"${k}=${v}\""
    }.join(' ')

    // Platform argument
    def platformStr = platform ? "--platform ${platform}" : ''

    // No cache argument
    def noCacheStr = noCache ? '--no-cache' : ''

    // Build command
    def buildCmd = """
        ${runtime} build \
            -t ${fullImageRef} \
            -f ${dockerfile} \
            ${buildArgsStr} \
            ${labelsStr} \
            ${platformStr} \
            ${noCacheStr} \
            ${context}
    """.trim().replaceAll(/\s+/, ' ')

    echo "Building image..."

    def exitCode = sh(
        script: buildCmd,
        returnStatus: true
    )

    if (exitCode != 0) {
        error "Image build failed with exit code ${exitCode}"
    }

    // Get image digest (local ID before push)
    def digest = sh(
        script: "${runtime} inspect --format='{{.Id}}' ${fullImageRef} 2>/dev/null || echo 'unknown'",
        returnStdout: true
    ).trim()
    echo "Image built: ${fullImageRef}"
    echo "Digest: ${digest}"

    // Store build info
    def buildInfo = [
        image: fullImageRef,
        digest: digest,
        dockerfile: dockerfile,
        context: context,
        buildArgs: buildArgs,
        labels: allLabels,
        runtime: runtime,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]

    // Write build info to workspace
    writeFile(
        file: 'reports/image-build.json',
        text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(buildInfo))
    )

    return buildInfo
}

/**
 * Push image to registry
 */
def push(Map config = [:]) {
    def imageName = config.name ?: error("push requires 'name' parameter")
    def imageTag = config.tag ?: env.GIT_COMMIT?.take(8) ?: 'latest'
    def fullImageRef = "${imageName}:${imageTag}"

    def runtime = containerUtils.detectRuntime()

    echo "=== Push Image: ${fullImageRef} ==="

    // Login to registry if credentials provided
    if (config.credentialsId) {
        withCredentials([usernamePassword(
            credentialsId: config.credentialsId,
            usernameVariable: 'REGISTRY_USER',
            passwordVariable: 'REGISTRY_PASSWORD'
        )]) {
            def registry = imageName.split('/')[0]
            sh "${runtime} login -u \${REGISTRY_USER} -p \${REGISTRY_PASSWORD} ${registry}"
        }
    }

    def exitCode = sh(
        script: "${runtime} push ${fullImageRef}",
        returnStatus: true
    )

    if (exitCode != 0) {
        error "Image push failed with exit code ${exitCode}"
    }

    // Get pushed digest
    def digest = sh(
        script: "${runtime} inspect --format='{{index .RepoDigests 0}}' ${fullImageRef} 2>/dev/null | cut -d@ -f2 || echo 'unknown'",
        returnStdout: true
    ).trim()

    echo "Image pushed: ${fullImageRef}"
    echo "Digest: ${digest}"

    return [image: fullImageRef, digest: digest]
}

/**
 * Tag image with additional tags
 */
def tag(Map config = [:]) {
    def sourceImage = config.source ?: error("tag requires 'source' parameter")
    def targetImage = config.target ?: error("tag requires 'target' parameter")

    def runtime = containerUtils.detectRuntime()

    echo "Tagging ${sourceImage} as ${targetImage}"

    sh "${runtime} tag ${sourceImage} ${targetImage}"

    return targetImage
}

/**
 * Scan image for vulnerabilities
 */
def scan(Map config = [:]) {
    def imageName = config.name ?: error("scan requires 'name' parameter")
    def imageTag = config.tag ?: 'latest'
    def fullImageRef = "${imageName}:${imageTag}"
    def severities = config.severities ?: 'CRITICAL,HIGH'
    def outputFile = config.output ?: 'reports/image-vulnerabilities.json'

    echo "=== Scan Image: ${fullImageRef} ==="

    sh "mkdir -p \$(dirname ${outputFile})"

    def exitCode = sh(
        script: """
            if command -v trivy &> /dev/null; then
                trivy image \
                    --format json \
                    --output ${outputFile} \
                    --severity ${severities} \
                    ${fullImageRef}
            else
                docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    aquasec/trivy:latest \
                    image \
                        --format json \
                        --severity ${severities} \
                        ${fullImageRef} > ${outputFile}
            fi
        """,
        returnStatus: true
    )

    // Count vulnerabilities
    def vulnCount = sh(
        script: "jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0' ${outputFile} 2>/dev/null || echo 0",
        returnStdout: true
    ).trim().toInteger()

    echo "Vulnerabilities found: ${vulnCount}"
    echo "Report: ${outputFile}"

    return [vulnerabilities: vulnCount, reportFile: outputFile]
}
