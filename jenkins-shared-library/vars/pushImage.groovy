#!/usr/bin/env groovy

/**
 * Push Image Step
 *
 * Pushes container image to registry with optional authentication.
 *
 * Usage:
 *   pushImage(name: 'registry/myapp', tag: 'v1.0.0')
 *   pushImage(name: 'registry/myapp', tag: 'v1.0.0', credentialsId: 'registry-creds')
 */

def call(Map config = [:]) {
    def imageName = config.name ?: error("pushImage requires 'name' parameter")
    def imageTag = config.tag ?: env.GIT_COMMIT?.take(8) ?: 'latest'
    def credentialsId = config.credentialsId ?: ''

    echo "=== Push Image: ${imageName}:${imageTag} ==="

    // Detect container runtime (use shared utility)
    def runtime = containerUtils.detectRuntime()

    // Extract registry from image name for login
    def registry = extractRegistry(imageName)

    // Login if credentials provided
    if (credentialsId) {
        try {
            withCredentials([usernamePassword(
                credentialsId: credentialsId,
                usernameVariable: 'REGISTRY_USER',
                passwordVariable: 'REGISTRY_PASSWORD'
            )]) {
                def loginExitCode = sh(
                    script: "echo \${REGISTRY_PASSWORD} | ${runtime} login -u \${REGISTRY_USER} --password-stdin ${registry}",
                    returnStatus: true
                )
                if (loginExitCode != 0) {
                    // Try alternate login syntax for older versions
                    sh "${runtime} login -u \${REGISTRY_USER} -p \${REGISTRY_PASSWORD} ${registry}"
                }
            }
        } catch (Exception e) {
            echo "WARNING: Registry login failed: ${e.message}"
            echo "Attempting push without explicit login (may work for local/insecure registries)"
        }
    }

    // Push image with retry
    def pushSuccess = false
    def maxRetries = 3
    def retryDelay = 5

    for (int attempt = 1; attempt <= maxRetries && !pushSuccess; attempt++) {
        echo "Push attempt ${attempt}/${maxRetries}..."
        def exitCode = sh(
            script: "${runtime} push ${imageName}:${imageTag}",
            returnStatus: true
        )

        if (exitCode == 0) {
            pushSuccess = true
        } else if (attempt < maxRetries) {
            echo "Push failed, retrying in ${retryDelay} seconds..."
            sleep(retryDelay)
            retryDelay *= 2  // Exponential backoff
        }
    }

    if (!pushSuccess) {
        error "Image push failed after ${maxRetries} attempts"
    }

    // Get digest after successful push
    def digest = getDigestAfterPush(runtime, imageName, imageTag)

    echo "Image pushed successfully"
    echo "Full reference: ${imageName}@${digest}"

    return [
        image: "${imageName}:${imageTag}",
        imageWithDigest: "${imageName}@${digest}",
        digest: digest,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Extract registry hostname from image name
 */
def extractRegistry(String imageName) {
    def parts = imageName.split('/')
    if (parts.length >= 2 && (parts[0].contains('.') || parts[0].contains(':'))) {
        return parts[0]
    }
    // Default to Docker Hub
    return 'docker.io'
}

/**
 * Get image digest after push
 */
def getDigestAfterPush(String runtime, String imageName, String imageTag) {
    // Method 1: Try docker inspect for RepoDigests
    def digest = sh(
        script: """
            ${runtime} inspect --format='{{index .RepoDigests 0}}' ${imageName}:${imageTag} 2>/dev/null | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    // Method 2: Try manifest inspect
    digest = sh(
        script: """
            ${runtime} manifest inspect ${imageName}:${imageTag} 2>/dev/null | grep -o '"digest":\\s*"sha256:[a-f0-9]*"' | head -1 | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    // Method 3: Calculate from local image
    echo "WARNING: Could not retrieve digest from registry, calculating locally"
    digest = sh(
        script: """
            ${runtime} inspect --format='{{.Id}}' ${imageName}:${imageTag} 2>/dev/null | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    error "Failed to retrieve image digest for ${imageName}:${imageTag}"
}

