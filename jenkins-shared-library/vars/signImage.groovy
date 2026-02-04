#!/usr/bin/env groovy

/**
 * Sign Image Step
 *
 * Signs container images using Cosign (Sigstore).
 * Provides supply chain security by ensuring image provenance.
 *
 * Usage:
 *   signImage(image: 'registry/myapp:v1.0.0')
 *   signImage(image: 'registry/myapp:v1.0.0', keyPath: 'cosign.key')
 */

def call(Map config = [:]) {
    def image = config.image ?: error("signImage requires 'image' parameter")
    def keyPath = config.keyPath ?: 'cosign.key'
    def keyless = config.keyless ?: false
    def reportsDir = config.reportsDir ?: 'reports'
    def annotations = config.annotations ?: [:]
    def credentialsId = config.credentialsId ?: 'cosign-password'

    echo "=== Sign Image: ${image} ==="
    echo "Mode: ${keyless ? 'Keyless (OIDC)' : 'Key-based'}"

    // Create reports directory
    sh "mkdir -p ${reportsDir}"

    def signatureInfo = [:]

    if (keyless) {
        signatureInfo = signKeyless(image, annotations)
    } else {
        signatureInfo = signWithKey(image, keyPath, annotations, credentialsId)
    }

    // Write signature info to report
    writeFile(
        file: "${reportsDir}/signature.json",
        text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(signatureInfo))
    )

    echo "Image signed successfully"
    echo "Report: ${reportsDir}/signature.json"

    return signatureInfo
}

/**
 * Sign image with private key
 *
 * @param image Image reference to sign
 * @param keyPath Path to Cosign private key
 * @param annotations Additional annotations to add to signature
 * @param credentialsId Jenkins credential ID for Cosign password
 */
def signWithKey(String image, String keyPath, Map annotations, String credentialsId) {
    // Validate key exists
    if (!fileExists(keyPath)) {
        error "Signing key not found: ${keyPath}"
    }

    // Validate image uses digest for immutability
    if (!image.contains('@sha256:')) {
        echo "WARNING: Image should use digest (@sha256:...) for signing"
    }

    // Standard annotations for traceability
    def standardAnnotations = [
        'build.number': env.BUILD_NUMBER ?: 'unknown',
        'build.url': env.BUILD_URL ?: 'unknown',
        'git.commit': env.GIT_COMMIT ?: 'unknown',
        'git.branch': env.GIT_BRANCH ?: 'unknown',
        'signed.timestamp': new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]

    def allAnnotations = standardAnnotations + annotations
    def annotationsArgs = allAnnotations.collect { k, v ->
        "-a ${k}=${v}"
    }.join(' ')

    echo "Signing image with key: ${keyPath}"

    // Get COSIGN_PASSWORD from credentials
    withCredentials([string(credentialsId: credentialsId, variable: 'COSIGN_PASSWORD')]) {
        def exitCode = sh(
            script: """
                if command -v cosign &> /dev/null; then
                    cosign sign \
                        --key ${keyPath} \
                        ${annotationsArgs} \
                        --yes \
                        ${image}
                else
                    docker run --rm \
                        -e COSIGN_PASSWORD=\${COSIGN_PASSWORD} \
                        -v \$(pwd):/workspace \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        gcr.io/projectsigstore/cosign:latest \
                        sign \
                            --key /workspace/${keyPath} \
                            ${annotationsArgs} \
                            --yes \
                            ${image}
                fi
            """,
            returnStatus: true
        )

        if (exitCode != 0) {
            error "Image signing failed with exit code ${exitCode}"
        }
    }

    return [
        image: image,
        mode: 'key-based',
        keyPath: keyPath,
        annotations: allAnnotations,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Sign image with keyless OIDC flow (Sigstore Fulcio/Rekor)
 */
def signKeyless(String image, Map annotations) {
    echo "Signing image with keyless OIDC flow"
    echo "WARNING: Keyless signing requires OIDC token (GitHub Actions, GitLab CI, etc.)"

    def standardAnnotations = [
        'build.number': env.BUILD_NUMBER ?: 'unknown',
        'build.url': env.BUILD_URL ?: 'unknown',
        'git.commit': env.GIT_COMMIT ?: 'unknown',
        'signed.timestamp': new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]

    def allAnnotations = standardAnnotations + annotations
    def annotationsArgs = allAnnotations.collect { k, v ->
        "-a ${k}=${v}"
    }.join(' ')

    def exitCode = sh(
        script: """
            if command -v cosign &> /dev/null; then
                COSIGN_EXPERIMENTAL=1 cosign sign \
                    ${annotationsArgs} \
                    --yes \
                    ${image}
            else
                docker run --rm \
                    -e COSIGN_EXPERIMENTAL=1 \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    gcr.io/projectsigstore/cosign:latest \
                    sign \
                        ${annotationsArgs} \
                        --yes \
                        ${image}
            fi
        """,
        returnStatus: true
    )

    if (exitCode != 0) {
        error "Keyless signing failed with exit code ${exitCode}"
    }

    return [
        image: image,
        mode: 'keyless',
        annotations: allAnnotations,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Verify image signature
 */
def verify(Map config = [:]) {
    def image = config.image ?: error("verify requires 'image' parameter")
    def keyPath = config.keyPath ?: 'cosign.pub'
    def keyless = config.keyless ?: false

    echo "=== Verify Image Signature: ${image} ==="

    def verified = false

    if (keyless) {
        verified = verifyKeyless(image)
    } else {
        verified = verifyWithKey(image, keyPath)
    }

    if (!verified) {
        error "Image signature verification failed for ${image}"
    }

    echo "Signature verified successfully"

    return [
        image: image,
        verified: verified,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Verify signature with public key
 */
def verifyWithKey(String image, String keyPath) {
    if (!fileExists(keyPath)) {
        error "Public key not found: ${keyPath}"
    }

    def exitCode = sh(
        script: """
            if command -v cosign &> /dev/null; then
                cosign verify \
                    --key ${keyPath} \
                    ${image}
            else
                docker run --rm \
                    -v \$(pwd):/workspace \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    gcr.io/projectsigstore/cosign:latest \
                    verify \
                        --key /workspace/${keyPath} \
                        ${image}
            fi
        """,
        returnStatus: true
    )

    return exitCode == 0
}

/**
 * Verify keyless signature
 */
def verifyKeyless(String image) {
    echo "Verifying keyless signature (checking Rekor transparency log)"

    def exitCode = sh(
        script: """
            if command -v cosign &> /dev/null; then
                COSIGN_EXPERIMENTAL=1 cosign verify ${image}
            else
                docker run --rm \
                    -e COSIGN_EXPERIMENTAL=1 \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    gcr.io/projectsigstore/cosign:latest \
                    verify ${image}
            fi
        """,
        returnStatus: true
    )

    return exitCode == 0
}

/**
 * Generate Cosign key pair
 *
 * @param outputDir Directory to store generated keys
 * @param keyName Base name for key files (default: cosign)
 * @param credentialsId Jenkins credential ID for Cosign password
 */
def generateKey(Map config = [:]) {
    def outputDir = config.outputDir ?: '.'
    def keyName = config.keyName ?: 'cosign'
    def credentialsId = config.credentialsId ?: 'cosign-password'

    echo "=== Generate Cosign Key Pair ==="

    withCredentials([string(credentialsId: credentialsId, variable: 'COSIGN_PASSWORD')]) {
        sh """
            cd ${outputDir}
            if command -v cosign &> /dev/null; then
                cosign generate-key-pair
            else
                docker run --rm \
                    -e COSIGN_PASSWORD=\${COSIGN_PASSWORD} \
                    -v \$(pwd):/workspace \
                    -w /workspace \
                    gcr.io/projectsigstore/cosign:latest \
                    generate-key-pair
            fi
        """
    }

    echo "Key pair generated:"
    echo "  Private key: ${outputDir}/${keyName}.key"
    echo "  Public key: ${outputDir}/${keyName}.pub"

    return [
        privateKey: "${outputDir}/${keyName}.key",
        publicKey: "${outputDir}/${keyName}.pub"
    ]
}
