package org.acme

/**
 * Pipeline Configuration Class
 *
 * Centralized configuration management for Golden Path pipelines.
 * Provides type-safe configuration with sensible defaults.
 */
class PipelineConfig implements Serializable {

    // Application settings
    String appName
    String buildTool = 'node'
    String registry = 'localhost:5000'

    // Security settings
    boolean enableSast = true
    boolean enableSca = true
    boolean enableSecrets = true
    boolean failOnSecurityFindings = true

    // Quality settings
    String sonarqubeServer = 'SonarQube'
    boolean sonarqubeQualityGate = true

    // Supply chain settings
    boolean enableSbom = true
    boolean enableSigning = true
    String cosignKeyPath = 'cosign.key'

    // GitOps settings
    boolean enableGitOps = true
    String gitopsRepo = ''
    String targetEnv = 'dev'

    // Build settings
    String dockerfile = 'Dockerfile'
    String buildContext = '.'
    Map<String, String> buildArgs = [:]

    // Notification settings
    String slackChannel = ''

    // Emergency mode
    boolean emergency = false
    String emergencyJustification = ''

    /**
     * Create config from Map
     */
    static PipelineConfig fromMap(Map config) {
        def pipelineConfig = new PipelineConfig()

        config.each { key, value ->
            if (pipelineConfig.hasProperty(key)) {
                pipelineConfig[key] = value
            }
        }

        return pipelineConfig
    }

    /**
     * Validate configuration
     */
    List<String> validate() {
        def errors = []

        if (!appName) {
            errors << "appName is required"
        }

        if (appName && !appName.matches(/^[a-z0-9-]+$/)) {
            errors << "appName must be lowercase alphanumeric with hyphens only"
        }

        if (!['node', 'maven', 'gradle', 'python', 'go'].contains(buildTool)) {
            errors << "buildTool must be one of: node, maven, gradle, python, go"
        }

        if (emergency && !emergencyJustification) {
            errors << "emergency mode requires emergencyJustification"
        }

        return errors
    }

    /**
     * Check if config is valid
     */
    boolean isValid() {
        return validate().isEmpty()
    }

    /**
     * Convert to Map for serialization
     */
    Map toMap() {
        return [
            appName: appName,
            buildTool: buildTool,
            registry: registry,
            enableSast: enableSast,
            enableSca: enableSca,
            enableSecrets: enableSecrets,
            failOnSecurityFindings: failOnSecurityFindings,
            sonarqubeServer: sonarqubeServer,
            sonarqubeQualityGate: sonarqubeQualityGate,
            enableSbom: enableSbom,
            enableSigning: enableSigning,
            cosignKeyPath: cosignKeyPath,
            enableGitOps: enableGitOps,
            gitopsRepo: gitopsRepo,
            targetEnv: targetEnv,
            dockerfile: dockerfile,
            buildContext: buildContext,
            buildArgs: buildArgs,
            slackChannel: slackChannel,
            emergency: emergency,
            emergencyJustification: emergencyJustification
        ]
    }

    @Override
    String toString() {
        return "PipelineConfig(appName=${appName}, buildTool=${buildTool}, registry=${registry})"
    }
}
