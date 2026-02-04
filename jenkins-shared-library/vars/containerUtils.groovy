#!/usr/bin/env groovy

/**
 * Container Utilities
 *
 * Shared utility functions for container operations.
 * Use this to avoid code duplication across pipeline steps.
 *
 * Usage:
 *   def runtime = containerUtils.detectRuntime()
 *   def digest = containerUtils.getImageDigest('registry/app:tag')
 */

/**
 * Detect available container runtime
 *
 * Checks for podman first (preferred in OpenShift/RHEL environments),
 * then falls back to docker.
 *
 * @return String 'podman' or 'docker'
 * @throws error if no container runtime is available
 */
def detectRuntime() {
    def podmanAvailable = sh(script: 'command -v podman >/dev/null 2>&1', returnStatus: true) == 0
    def dockerAvailable = sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0

    if (podmanAvailable) {
        return 'podman'
    } else if (dockerAvailable) {
        return 'docker'
    } else {
        error "No container runtime found. Install Docker or Podman."
    }
}

/**
 * Get image digest from registry
 *
 * Attempts multiple methods to retrieve the image digest:
 * 1. RepoDigests from local inspect (works after push)
 * 2. Manifest inspect from registry
 * 3. Local image ID as fallback
 *
 * @param imageName Image name without tag
 * @param imageTag Image tag
 * @param runtime Optional. Container runtime ('podman' or 'docker')
 * @return String Image digest in format sha256:xxx
 */
def getImageDigest(String imageName, String imageTag, String runtime = null) {
    if (!runtime) {
        runtime = detectRuntime()
    }

    def fullImage = "${imageName}:${imageTag}"

    // Method 1: Try RepoDigests (available after push)
    def digest = sh(
        script: """
            ${runtime} inspect --format='{{index .RepoDigests 0}}' ${fullImage} 2>/dev/null | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    // Method 2: Try manifest inspect
    digest = sh(
        script: """
            ${runtime} manifest inspect ${fullImage} 2>/dev/null | grep -o '"digest":\\s*"sha256:[a-f0-9]*"' | head -1 | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    // Method 3: Local image ID as fallback
    echo "WARNING: Could not retrieve digest from registry, using local image ID"
    digest = sh(
        script: """
            ${runtime} inspect --format='{{.Id}}' ${fullImage} 2>/dev/null | grep -o 'sha256:[a-f0-9]*' || echo ''
        """,
        returnStdout: true
    ).trim()

    if (digest && digest.matches(/^sha256:[a-f0-9]{64}$/)) {
        return digest
    }

    error "Failed to retrieve image digest for ${fullImage}"
}

/**
 * Validate image digest format
 *
 * @param digest Digest string to validate
 * @return Boolean true if valid sha256 digest
 */
def isValidDigest(String digest) {
    return digest && digest.matches(/^sha256:[a-f0-9]{64}$/)
}

/**
 * Build full image reference with digest
 *
 * @param imageName Image name (registry/repo)
 * @param digest Image digest
 * @return String Full image reference (registry/repo@sha256:xxx)
 */
def imageWithDigest(String imageName, String digest) {
    if (!isValidDigest(digest)) {
        error "Invalid digest format: ${digest}"
    }
    // Remove tag if present
    def baseImage = imageName.contains(':') ? imageName.split(':')[0] : imageName
    return "${baseImage}@${digest}"
}

/**
 * Extract registry hostname from image name
 *
 * @param imageName Full image name
 * @return String Registry hostname or 'docker.io' for Docker Hub
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
 * Check if image exists in registry
 *
 * @param image Full image reference
 * @param runtime Optional. Container runtime
 * @return Boolean true if image exists
 */
def imageExists(String image, String runtime = null) {
    if (!runtime) {
        runtime = detectRuntime()
    }

    def exitCode = sh(
        script: "${runtime} manifest inspect ${image} >/dev/null 2>&1",
        returnStatus: true
    )

    return exitCode == 0
}

// Alias for backward compatibility
def call() {
    return this
}
