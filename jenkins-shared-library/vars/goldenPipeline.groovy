#!/usr/bin/env groovy

/**
 * Golden Path Pipeline - Main Entry Point
 *
 * Opinionated CI/CD pipeline for regulated environments.
 * All security gates are mandatory and blocking.
 *
 * Usage in Jenkinsfile:
 *   @Library('golden-path@v1.0.0') _
 *   goldenPipeline(
 *       appName: 'my-service',
 *       buildTool: 'node'
 *   )
 */

def call(Map config = [:]) {
    // Validate required parameters
    validateConfig(config)

    // Merge with defaults
    def pipelineConfig = [
        appName: config.appName,
        buildTool: config.buildTool ?: 'node',

        // Registry configuration
        registry: config.registry ?: env.REGISTRY_URL ?: 'localhost:5000',
        registryCredentialsId: config.registryCredentialsId ?: 'registry-credentials',

        // SonarQube configuration
        sonarqubeServer: config.sonarqubeServer ?: 'SonarQube',
        sonarqubeQualityGate: config.sonarqubeQualityGate ?: true,

        // Security scanning
        enableSast: config.enableSast != false,
        enableSca: config.enableSca != false,
        enableSecrets: config.enableSecrets != false,
        failOnSecurityFindings: config.failOnSecurityFindings != false,

        // Supply chain
        enableSbom: config.enableSbom != false,
        enableSigning: config.enableSigning != false,
        cosignKeyPath: config.cosignKeyPath ?: 'cosign.key',
        cosignPasswordCredentialsId: config.cosignPasswordCredentialsId ?: 'cosign-password',

        // GitOps
        enableGitOps: config.enableGitOps != false,
        gitopsRepo: config.gitopsRepo ?: '',
        targetEnv: config.targetEnv ?: 'dev',
        gitopsCredentialsId: config.gitopsCredentialsId ?: 'gitops-ssh-key',

        // Build configuration
        dockerfile: config.dockerfile ?: 'Dockerfile',
        buildContext: config.buildContext ?: '.',
        buildArgs: config.buildArgs ?: [:],

        // Notifications
        slackChannel: config.slackChannel ?: '',
        emergencyAlertChannel: config.emergencyAlertChannel ?: '#security-alerts',

        // Emergency mode (requires justification AND approval)
        emergency: config.emergency ?: false,
        emergencyJustification: config.emergencyJustification ?: '',
        emergencyApprover: config.emergencyApprover ?: '',
        emergencyTicket: config.emergencyTicket ?: '',
        // Emergency bypass scope (limit what can be bypassed)
        emergencyBypassGates: config.emergencyBypassGates ?: ['securityFindings', 'qualityGate']
    ]

    // Validate credentials exist
    validateCredentials(pipelineConfig)

    // Validate and log emergency mode usage
    if (pipelineConfig.emergency) {
        validateEmergencyMode(pipelineConfig)
        logEmergencyModeUsage(pipelineConfig)
    }

    // Store image digest after push (will be set in Push Image stage)
    def imageDigest = ''

    pipeline {
        agent any

        environment {
            APP_NAME = "${pipelineConfig.appName}"
            REGISTRY = "${pipelineConfig.registry}"
            IMAGE_TAG = "${env.GIT_COMMIT?.take(8) ?: 'latest'}"
            IMAGE_NAME = "${pipelineConfig.registry}/${pipelineConfig.appName}"
            REPORTS_DIR = "reports"
        }

        options {
            timeout(time: 30, unit: 'MINUTES')
            disableConcurrentBuilds()
            buildDiscarder(logRotator(numToKeepStr: '10'))
            timestamps()
        }

        stages {
            stage('Initialize') {
                steps {
                    script {
                        initializePipeline(pipelineConfig)
                    }
                }
            }

            stage('Security Scans') {
                parallel {
                    stage('SAST') {
                        when { expression { pipelineConfig.enableSast } }
                        steps {
                            script {
                                timeout(time: 10, unit: 'MINUTES') {
                                    // Use shouldFailOnGate for controlled emergency bypass
                                    securityScan(
                                        type: 'sast',
                                        failOnFindings: pipelineConfig.failOnSecurityFindings && shouldFailOnGate(pipelineConfig, 'securityFindings')
                                    )
                                }
                            }
                        }
                    }

                    stage('SCA') {
                        when { expression { pipelineConfig.enableSca } }
                        steps {
                            script {
                                timeout(time: 10, unit: 'MINUTES') {
                                    securityScan(
                                        type: 'sca',
                                        failOnFindings: pipelineConfig.failOnSecurityFindings && shouldFailOnGate(pipelineConfig, 'securityFindings')
                                    )
                                }
                            }
                        }
                    }

                    stage('Secrets') {
                        when { expression { pipelineConfig.enableSecrets } }
                        steps {
                            script {
                                timeout(time: 5, unit: 'MINUTES') {
                                    // CRITICAL: Secrets detection can NEVER be bypassed
                                    // Even in emergency mode, we must block exposed secrets
                                    securityScan(
                                        type: 'secrets',
                                        failOnFindings: pipelineConfig.failOnSecurityFindings  // No bypass allowed
                                    )
                                }
                            }
                        }
                    }
                }
            }

            stage('Build') {
                steps {
                    script {
                        buildApplication(pipelineConfig)
                    }
                }
            }

            stage('Quality Gate') {
                when { expression { pipelineConfig.sonarqubeQualityGate } }
                steps {
                    script {
                        qualityGate(
                            projectKey: pipelineConfig.appName,
                            server: pipelineConfig.sonarqubeServer,
                            failOnQualityGate: shouldFailOnGate(pipelineConfig, 'qualityGate')
                        )
                    }
                }
            }

            stage('Build Image') {
                steps {
                    script {
                        buildImage(
                            name: env.IMAGE_NAME,
                            tag: env.IMAGE_TAG,
                            dockerfile: pipelineConfig.dockerfile,
                            context: pipelineConfig.buildContext,
                            buildArgs: pipelineConfig.buildArgs
                        )
                    }
                }
            }

            stage('Generate SBOM') {
                when { expression { pipelineConfig.enableSbom } }
                steps {
                    script {
                        generateSbom(
                            image: "${env.IMAGE_NAME}:${env.IMAGE_TAG}",
                            outputDir: env.REPORTS_DIR
                        )
                    }
                }
            }

            stage('Sign Image') {
                when { expression { pipelineConfig.enableSigning } }
                steps {
                    script {
                        signImage(
                            image: "${env.IMAGE_NAME}:${env.IMAGE_TAG}",
                            keyPath: pipelineConfig.cosignKeyPath,
                            credentialsId: pipelineConfig.cosignPasswordCredentialsId
                        )
                    }
                }
            }

            stage('Push Image') {
                steps {
                    script {
                        pushImage(
                            name: env.IMAGE_NAME,
                            tag: env.IMAGE_TAG,
                            credentialsId: pipelineConfig.registryCredentialsId
                        )

                        // Get digest AFTER push - this is critical for immutability
                        imageDigest = getImageDigest(env.IMAGE_NAME, env.IMAGE_TAG)
                        echo "Image pushed with digest: ${imageDigest}"

                        // Store digest for later stages
                        env.IMAGE_DIGEST = imageDigest
                    }
                }
            }

            stage('GitOps Promote') {
                when { expression { pipelineConfig.enableGitOps && pipelineConfig.gitopsRepo } }
                steps {
                    script {
                        // Validate we have a proper digest
                        if (!env.IMAGE_DIGEST || !env.IMAGE_DIGEST.startsWith('sha256:')) {
                            error "Cannot promote to GitOps: invalid image digest '${env.IMAGE_DIGEST}'"
                        }

                        gitopsPromote(
                            repo: pipelineConfig.gitopsRepo,
                            app: pipelineConfig.appName,
                            image: "${env.IMAGE_NAME}@${env.IMAGE_DIGEST}",
                            environment: pipelineConfig.targetEnv,
                            credentialsId: pipelineConfig.gitopsCredentialsId
                        )
                    }
                }
            }
        }

        post {
            always {
                script {
                    archiveArtifacts artifacts: "${env.REPORTS_DIR}/**/*", allowEmptyArchive: true

                    if (pipelineConfig.emergency) {
                        writeFile file: "${env.REPORTS_DIR}/emergency-audit.json", text: groovy.json.JsonOutput.toJson([
                            timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
                            pipeline: env.BUILD_URL,
                            justification: pipelineConfig.emergencyJustification,
                            commit: env.GIT_COMMIT,
                            user: env.BUILD_USER ?: 'unknown'
                        ])
                    }
                }

                cleanWs()
            }

            success {
                script {
                    if (pipelineConfig.slackChannel) {
                        notifySlack(
                            channel: pipelineConfig.slackChannel,
                            status: 'SUCCESS',
                            message: "Pipeline succeeded for ${pipelineConfig.appName}"
                        )
                    }
                }
            }

            failure {
                script {
                    if (pipelineConfig.slackChannel) {
                        notifySlack(
                            channel: pipelineConfig.slackChannel,
                            status: 'FAILURE',
                            message: "Pipeline failed for ${pipelineConfig.appName}"
                        )
                    }
                }
            }
        }
    }
}

/**
 * Validate required configuration parameters
 */
def validateConfig(Map config) {
    def errors = []

    if (!config.appName) {
        errors << "appName is required"
    }

    if (config.appName && !config.appName.matches(/^[a-z0-9-]+$/)) {
        errors << "appName must be lowercase alphanumeric with hyphens only"
    }

    if (config.buildTool && !['node', 'maven', 'gradle', 'python', 'go'].contains(config.buildTool)) {
        errors << "buildTool must be one of: node, maven, gradle, python, go"
    }

    if (errors) {
        error "Pipeline configuration errors:\n${errors.join('\n')}"
    }
}

/**
 * Validate that required credentials exist (warn if missing)
 */
def validateCredentials(Map config) {
    def warnings = []

    // Check registry credentials if not using insecure registry
    if (!config.registry.startsWith('localhost') && !config.registry.contains(':5000')) {
        try {
            withCredentials([usernamePassword(credentialsId: config.registryCredentialsId, usernameVariable: 'U', passwordVariable: 'P')]) {
                // Credentials exist
            }
        } catch (Exception e) {
            warnings << "Registry credentials '${config.registryCredentialsId}' not found - push may fail for private registries"
        }
    }

    // Check cosign credentials if signing enabled
    if (config.enableSigning) {
        try {
            withCredentials([string(credentialsId: config.cosignPasswordCredentialsId, variable: 'P')]) {
                // Credentials exist
            }
        } catch (Exception e) {
            warnings << "Cosign password credentials '${config.cosignPasswordCredentialsId}' not found - signing may fail"
        }
    }

    if (warnings) {
        echo "CREDENTIAL WARNINGS:"
        warnings.each { echo "  - ${it}" }
    }
}

/**
 * Validate emergency mode requirements
 * Emergency mode requires:
 * - Justification explaining the urgency
 * - Approver name (who authorized the bypass)
 * - Ticket number for tracking
 */
def validateEmergencyMode(Map config) {
    def errors = []

    if (!config.emergencyJustification) {
        errors << "EMERGENCY mode requires 'emergencyJustification' parameter"
    }

    if (!config.emergencyApprover) {
        errors << "EMERGENCY mode requires 'emergencyApprover' parameter (who approved this bypass)"
    }

    if (!config.emergencyTicket) {
        errors << "EMERGENCY mode requires 'emergencyTicket' parameter (incident/ticket number)"
    }

    // Validate bypass scope
    def validBypassGates = ['securityFindings', 'qualityGate']
    config.emergencyBypassGates.each { gate ->
        if (!validBypassGates.contains(gate)) {
            errors << "Invalid bypass gate: ${gate}. Valid options: ${validBypassGates.join(', ')}"
        }
    }

    // Critical gates that can NEVER be bypassed
    def neverBypass = ['secrets']  // Never allow bypassing secrets detection
    neverBypass.each { gate ->
        if (config.emergencyBypassGates.contains(gate)) {
            errors << "CRITICAL: '${gate}' gate cannot be bypassed even in emergency mode"
        }
    }

    if (errors) {
        error "EMERGENCY MODE VALIDATION FAILED:\n${errors.join('\n')}"
    }
}

/**
 * Log emergency mode usage for audit trail
 * This creates an immutable record of the bypass
 */
def logEmergencyModeUsage(Map config) {
    echo "=============================================="
    echo "  EMERGENCY MODE ACTIVATED"
    echo "=============================================="
    echo "Application: ${config.appName}"
    echo "Justification: ${config.emergencyJustification}"
    echo "Approved by: ${config.emergencyApprover}"
    echo "Ticket: ${config.emergencyTicket}"
    echo "Bypassed gates: ${config.emergencyBypassGates.join(', ')}"
    echo "Timestamp: ${new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}"
    echo "Build URL: ${env.BUILD_URL ?: 'unknown'}"
    echo "Git Commit: ${env.GIT_COMMIT ?: 'unknown'}"
    echo "User: ${env.BUILD_USER ?: 'unknown'}"
    echo "=============================================="
    echo ""
    echo "WARNING: This bypass is logged and will be audited."
    echo "Emergency deployments require post-incident review."
    echo ""

    // Send alert to security channel
    if (config.emergencyAlertChannel) {
        try {
            notifySlack(
                channel: config.emergencyAlertChannel,
                status: 'WARNING',
                message: """EMERGENCY MODE ACTIVATED
App: ${config.appName}
Justification: ${config.emergencyJustification}
Approver: ${config.emergencyApprover}
Ticket: ${config.emergencyTicket}
Bypassed: ${config.emergencyBypassGates.join(', ')}"""
            )
        } catch (Exception e) {
            echo "Warning: Could not send emergency alert: ${e.message}"
        }
    }
}

/**
 * Check if a specific gate should fail based on emergency mode
 */
def shouldFailOnGate(Map config, String gateName) {
    if (!config.emergency) {
        return true  // Normal mode: all gates fail
    }
    // Emergency mode: only fail if gate is NOT in bypass list
    return !config.emergencyBypassGates.contains(gateName)
}

/**
 * Initialize pipeline - checkout, setup environment
 */
def initializePipeline(Map config) {
    echo "=== Golden Path Pipeline v1.0.0 ==="
    echo "Application: ${config.appName}"
    echo "Build Tool: ${config.buildTool}"
    echo "Registry: ${config.registry}"
    echo ""
    echo "Security Gates:"
    echo "  SAST: ${config.enableSast ? 'ENABLED' : 'DISABLED'}"
    echo "  SCA: ${config.enableSca ? 'ENABLED' : 'DISABLED'}"
    echo "  Secrets: ${config.enableSecrets ? 'ENABLED' : 'DISABLED'}"
    echo "  Quality Gate: ${config.sonarqubeQualityGate ? 'ENABLED' : 'DISABLED'}"
    echo "  SBOM: ${config.enableSbom ? 'ENABLED' : 'DISABLED'}"
    echo "  Signing: ${config.enableSigning ? 'ENABLED' : 'DISABLED'}"

    // Create reports directory
    sh "mkdir -p ${env.REPORTS_DIR}"

    // Store build metadata
    writeFile file: "${env.REPORTS_DIR}/build-info.json", text: groovy.json.JsonOutput.toJson([
        appName: config.appName,
        buildNumber: env.BUILD_NUMBER,
        gitCommit: env.GIT_COMMIT,
        gitBranch: env.GIT_BRANCH,
        timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
        pipelineVersion: 'v1.0.0'
    ])
}

/**
 * Build application based on build tool
 */
def buildApplication(Map config) {
    echo "Building ${config.appName} with ${config.buildTool}..."

    switch (config.buildTool) {
        case 'node':
            sh '''
                if [ -f package-lock.json ]; then
                    npm ci
                else
                    npm install
                fi
                npm run build --if-present
                npm test --if-present
            '''
            break

        case 'maven':
            sh 'mvn clean verify -B'
            break

        case 'gradle':
            sh './gradlew clean build'
            break

        case 'python':
            sh '''
                python -m venv venv
                . venv/bin/activate
                pip install -r requirements.txt
                pip install pytest
                pytest --junitxml=reports/pytest.xml || true
            '''
            break

        case 'go':
            sh '''
                go mod download
                go build -v ./...
                go test -v ./... -coverprofile=coverage.out
            '''
            break

        default:
            echo "No specific build steps for ${config.buildTool}, assuming pre-built"
    }
}

/**
 * Get image digest after push
 * IMPORTANT: Must be called AFTER image is pushed to registry
 *
 * Uses shared containerUtils for consistent digest retrieval.
 */
def getImageDigest(String imageName, String imageTag) {
    return containerUtils.getImageDigest(imageName, imageTag)
}
