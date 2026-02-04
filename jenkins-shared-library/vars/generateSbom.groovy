#!/usr/bin/env groovy

/**
 * Generate SBOM Step
 *
 * Generates Software Bill of Materials (SBOM) in CycloneDX format.
 * Essential for supply chain security and vulnerability management.
 *
 * Usage:
 *   generateSbom(image: 'registry/myapp:v1.0.0')
 *   generateSbom(path: './src', outputDir: 'reports')
 */

def call(Map config = [:]) {
    def image = config.image
    def targetPath = config.path ?: '.'
    def outputDir = config.outputDir ?: 'reports'
    def format = config.format ?: 'cyclonedx-json'
    def tool = config.tool ?: 'trivy'

    echo "=== Generate SBOM ==="
    echo "Target: ${image ?: targetPath}"
    echo "Format: ${format}"
    echo "Tool: ${tool}"

    // Create output directory
    sh "mkdir -p ${outputDir}"

    def sbomResult = [:]

    if (image) {
        sbomResult = generateImageSbom(image, outputDir, format, tool)
    } else {
        sbomResult = generateFilesystemSbom(targetPath, outputDir, format, tool)
    }

    // Validate SBOM
    validateSbom(sbomResult.outputFile)

    // Generate summary
    def summary = analyzeSbom(sbomResult.outputFile)

    echo "SBOM generated: ${sbomResult.outputFile}"
    echo "Components: ${summary.componentCount}"
    echo "Licenses: ${summary.licenses.take(5).join(', ')}${summary.licenses.size() > 5 ? '...' : ''}"

    // Write summary
    writeFile(
        file: "${outputDir}/sbom-summary.json",
        text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(summary))
    )

    return sbomResult + [summary: summary]
}

/**
 * Generate SBOM for container image
 */
def generateImageSbom(String image, String outputDir, String format, String tool) {
    def outputFile = "${outputDir}/sbom-cyclonedx.json"

    switch (tool) {
        case 'trivy':
            generateWithTrivy(image, outputFile, 'image')
            break
        case 'syft':
            generateWithSyft(image, outputFile, 'image')
            break
        default:
            error "Unknown SBOM tool: ${tool}"
    }

    return [
        target: image,
        targetType: 'image',
        outputFile: outputFile,
        format: format,
        tool: tool,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Generate SBOM for filesystem/source code
 */
def generateFilesystemSbom(String targetPath, String outputDir, String format, String tool) {
    def outputFile = "${outputDir}/sbom-cyclonedx.json"

    switch (tool) {
        case 'trivy':
            generateWithTrivy(targetPath, outputFile, 'fs')
            break
        case 'syft':
            generateWithSyft(targetPath, outputFile, 'fs')
            break
        default:
            error "Unknown SBOM tool: ${tool}"
    }

    return [
        target: targetPath,
        targetType: 'filesystem',
        outputFile: outputFile,
        format: format,
        tool: tool,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Generate SBOM using Trivy
 */
def generateWithTrivy(String target, String outputFile, String targetType) {
    def trivyCmd = targetType == 'image' ? 'image' : 'fs'

    def exitCode = sh(
        script: """
            if command -v trivy &> /dev/null; then
                trivy ${trivyCmd} \
                    --format cyclonedx \
                    --output ${outputFile} \
                    ${target}
            else
                docker run --rm \
                    -v \$(pwd):/workspace \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    aquasec/trivy:latest \
                    ${trivyCmd} \
                        --format cyclonedx \
                        --output /workspace/${outputFile} \
                        ${targetType == 'fs' ? '/workspace/' + target : target}
            fi
        """,
        returnStatus: true
    )

    if (exitCode != 0) {
        error "SBOM generation with Trivy failed"
    }
}

/**
 * Generate SBOM using Syft
 */
def generateWithSyft(String target, String outputFile, String targetType) {
    def syftTarget = targetType == 'image' ? target : "dir:${target}"

    def exitCode = sh(
        script: """
            if command -v syft &> /dev/null; then
                syft ${syftTarget} \
                    --output cyclonedx-json=${outputFile}
            else
                docker run --rm \
                    -v \$(pwd):/workspace \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    anchore/syft:latest \
                    ${targetType == 'fs' ? '/workspace/' + target : target} \
                        --output cyclonedx-json=/workspace/${outputFile}
            fi
        """,
        returnStatus: true
    )

    if (exitCode != 0) {
        error "SBOM generation with Syft failed"
    }
}

/**
 * Validate generated SBOM
 */
def validateSbom(String sbomFile) {
    if (!fileExists(sbomFile)) {
        error "SBOM file not found: ${sbomFile}"
    }

    // Basic JSON validation
    def exitCode = sh(
        script: "jq empty ${sbomFile}",
        returnStatus: true
    )

    if (exitCode != 0) {
        error "SBOM file is not valid JSON: ${sbomFile}"
    }

    // Check for required CycloneDX fields
    def hasBomFormat = sh(
        script: "jq -e '.bomFormat' ${sbomFile} >/dev/null 2>&1",
        returnStatus: true
    )

    if (hasBomFormat != 0) {
        error "SBOM file missing required CycloneDX fields"
    }

    echo "SBOM validation passed"
}

/**
 * Analyze SBOM and return summary
 */
def analyzeSbom(String sbomFile) {
    def componentCount = sh(
        script: "jq '.components | length' ${sbomFile} 2>/dev/null || echo 0",
        returnStdout: true
    ).trim().toInteger()

    def licenses = []
    try {
        def licensesJson = sh(
            script: """
                jq -r '[.components[]?.licenses[]?.license.id // .components[]?.licenses[]?.license.name // empty] | unique | .[]' ${sbomFile} 2>/dev/null || true
            """,
            returnStdout: true
        ).trim()

        if (licensesJson) {
            licenses = licensesJson.split('\n').findAll { it }
        }
    } catch (Exception e) {
        echo "Warning: Could not extract licenses from SBOM"
    }

    // Get SBOM metadata
    def metadata = [:]
    try {
        def specVersion = sh(
            script: "jq -r '.specVersion // \"unknown\"' ${sbomFile}",
            returnStdout: true
        ).trim()

        metadata = [
            specVersion: specVersion,
            bomFormat: 'CycloneDX'
        ]
    } catch (Exception e) {
        // Ignore
    }

    return [
        componentCount: componentCount,
        licenses: licenses,
        metadata: metadata,
        analyzedAt: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Attach SBOM to container image
 *
 * Attaches SBOM as attestation using Cosign.
 * Uses the in-toto attestation format with CycloneDX predicate type.
 *
 * @param image Required. Image reference (should include digest)
 * @param sbom Optional. Path to SBOM file (default: reports/sbom-cyclonedx.json)
 * @param keyPath Optional. Path to Cosign private key (default: cosign.key)
 * @param credentialsId Optional. Jenkins credential ID for Cosign password
 */
def attach(Map config = [:]) {
    def image = config.image ?: error("attach requires 'image' parameter")
    def sbomFile = config.sbom ?: 'reports/sbom-cyclonedx.json'
    def keyPath = config.keyPath ?: 'cosign.key'
    def credentialsId = config.credentialsId ?: 'cosign-password'

    echo "=== Attach SBOM to Image ==="
    echo "Image: ${image}"
    echo "SBOM: ${sbomFile}"

    if (!fileExists(sbomFile)) {
        error "SBOM file not found: ${sbomFile}"
    }

    if (!fileExists(keyPath)) {
        error "Cosign key not found: ${keyPath}"
    }

    // Validate image uses digest for immutability
    if (!image.contains('@sha256:')) {
        echo "WARNING: Image should use digest (@sha256:...) for SBOM attestation"
    }

    withCredentials([string(credentialsId: credentialsId, variable: 'COSIGN_PASSWORD')]) {
        // Step 1: Attach SBOM as a layer (deprecated but still supported)
        def attachExitCode = sh(
            script: """
                if command -v cosign &> /dev/null; then
                    cosign attach sbom \
                        --sbom ${sbomFile} \
                        ${image} 2>&1 || true
                else
                    docker run --rm \
                        -e COSIGN_PASSWORD=\${COSIGN_PASSWORD} \
                        -v \$(pwd):/workspace \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        gcr.io/projectsigstore/cosign:latest \
                        attach sbom \
                            --sbom /workspace/${sbomFile} \
                            ${image} 2>&1 || true
                fi
            """,
            returnStatus: true
        )

        // Step 2: Create signed attestation (preferred method)
        // Using the standard CycloneDX predicate type URI
        def attestExitCode = sh(
            script: """
                if command -v cosign &> /dev/null; then
                    cosign attest \
                        --key ${keyPath} \
                        --predicate ${sbomFile} \
                        --type https://cyclonedx.org/bom \
                        --yes \
                        ${image}
                else
                    docker run --rm \
                        -e COSIGN_PASSWORD=\${COSIGN_PASSWORD} \
                        -v \$(pwd):/workspace \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        gcr.io/projectsigstore/cosign:latest \
                        attest \
                            --key /workspace/${keyPath} \
                            --predicate /workspace/${sbomFile} \
                            --type https://cyclonedx.org/bom \
                            --yes \
                            ${image}
                fi
            """,
            returnStatus: true
        )

        if (attestExitCode != 0) {
            error "SBOM attestation failed with exit code ${attestExitCode}"
        }
    }

    echo "SBOM attached and attested to image"

    return [
        image: image,
        sbom: sbomFile,
        predicateType: 'https://cyclonedx.org/bom',
        attachedAt: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    ]
}

/**
 * Query SBOM for specific component
 */
def query(Map config = [:]) {
    def sbomFile = config.sbom ?: 'reports/sbom-cyclonedx.json'
    def componentName = config.name
    def purl = config.purl

    if (!componentName && !purl) {
        error "query requires either 'name' or 'purl' parameter"
    }

    echo "=== Query SBOM ==="
    echo "SBOM: ${sbomFile}"
    echo "Query: ${componentName ?: purl}"

    def query = componentName ?
        ".components[] | select(.name | contains(\"${componentName}\"))" :
        ".components[] | select(.purl == \"${purl}\")"

    def result = sh(
        script: "jq '${query}' ${sbomFile}",
        returnStdout: true
    ).trim()

    if (!result || result == 'null') {
        echo "Component not found in SBOM"
        return null
    }

    return readJSON(text: result)
}
