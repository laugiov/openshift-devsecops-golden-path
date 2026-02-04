#!/usr/bin/env groovy

/**
 * Quality Gate Step
 *
 * Runs SonarQube analysis and enforces quality gate.
 * BLOCKS the build if quality gate fails (not warns).
 *
 * Usage:
 *   qualityGate(projectKey: 'my-service')
 *   qualityGate(projectKey: 'my-service', server: 'SonarQube', failOnQualityGate: true)
 */

def call(Map config = [:]) {
    def projectKey = config.projectKey ?: env.APP_NAME
    def serverName = config.server ?: 'SonarQube'
    def failOnQualityGate = config.failOnQualityGate != false
    def waitTimeout = config.waitTimeout ?: 5  // minutes
    def reportsDir = config.reportsDir ?: 'reports'

    if (!projectKey) {
        error "qualityGate requires projectKey parameter or APP_NAME environment variable"
    }

    echo "=== Quality Gate: ${projectKey} ==="
    echo "Server: ${serverName}"
    echo "Fail on gate failure: ${failOnQualityGate}"

    // Create reports directory
    sh "mkdir -p ${reportsDir}"

    def result = [:]

    try {
        // Run SonarQube analysis
        runSonarAnalysis(projectKey, serverName, config)

        // Wait for quality gate
        result = waitForQualityGate(projectKey, serverName, waitTimeout)

        // Store quality gate result
        writeQualityGateReport(result, reportsDir)

        // Evaluate result
        if (result.status != 'OK' && result.status != 'PASSED') {
            echo "QUALITY GATE FAILED: ${result.status}"

            if (result.conditions) {
                echo "Failed conditions:"
                result.conditions.findAll { it.status != 'OK' }.each { condition ->
                    echo "  - ${condition.metricKey}: ${condition.actualValue} (threshold: ${condition.errorThreshold})"
                }
            }

            if (failOnQualityGate) {
                error "Quality gate failed with status: ${result.status}"
            } else {
                echo "WARNING: Quality gate failed but failOnQualityGate=false"
            }
        } else {
            echo "QUALITY GATE PASSED"
        }

    } catch (Exception e) {
        if (e.message?.contains('Quality gate failed')) {
            throw e  // Re-throw our own error
        }
        // SonarQube might be unavailable
        echo "WARNING: Quality gate check failed: ${e.message}"

        if (failOnQualityGate) {
            error "Quality gate check failed and failOnQualityGate=true: ${e.message}"
        }
    }

    return result
}

/**
 * Run SonarQube analysis based on build tool
 */
def runSonarAnalysis(String projectKey, String serverName, Map config) {
    def buildTool = config.buildTool ?: detectBuildTool()
    def sonarProps = config.sonarProperties ?: [:]

    echo "Running SonarQube analysis for ${projectKey}..."
    echo "Detected build tool: ${buildTool}"

    withSonarQubeEnv(serverName) {
        switch (buildTool) {
            case 'maven':
                sh """
                    mvn sonar:sonar \
                        -Dsonar.projectKey=${projectKey} \
                        -Dsonar.projectName=${projectKey} \
                        ${buildSonarProperties(sonarProps)}
                """
                break

            case 'gradle':
                sh """
                    ./gradlew sonarqube \
                        -Dsonar.projectKey=${projectKey} \
                        -Dsonar.projectName=${projectKey} \
                        ${buildSonarProperties(sonarProps)}
                """
                break

            case 'node':
                // For Node.js, use sonar-scanner
                runSonarScanner(projectKey, sonarProps)
                break

            case 'python':
                runSonarScanner(projectKey, sonarProps)
                break

            case 'go':
                runSonarScanner(projectKey, sonarProps)
                break

            default:
                runSonarScanner(projectKey, sonarProps)
        }
    }
}

/**
 * Run sonar-scanner CLI
 */
def runSonarScanner(String projectKey, Map sonarProps) {
    def propsFile = "sonar-project.properties"
    def hasPropsFile = fileExists(propsFile)

    def scannerArgs = """
        -Dsonar.projectKey=${projectKey}
        -Dsonar.projectName=${projectKey}
        -Dsonar.sources=.
        ${buildSonarProperties(sonarProps)}
    """.trim().replaceAll(/\n\s+/, ' ')

    // Check if sonar-scanner is available, otherwise use Docker
    def exitCode = sh(
        script: """
            if command -v sonar-scanner &> /dev/null; then
                sonar-scanner ${scannerArgs}
            else
                docker run --rm \
                    -e SONAR_HOST_URL=\${SONAR_HOST_URL} \
                    -e SONAR_TOKEN=\${SONAR_AUTH_TOKEN} \
                    -v \$(pwd):/usr/src \
                    sonarsource/sonar-scanner-cli:latest \
                    ${scannerArgs}
            fi
        """,
        returnStatus: true
    )

    if (exitCode != 0) {
        error "SonarQube analysis failed with exit code ${exitCode}"
    }
}

/**
 * Wait for quality gate result from SonarQube
 */
def waitForQualityGate(String projectKey, String serverName, int timeoutMinutes) {
    echo "Waiting for quality gate result..."

    def result = [:]

    timeout(time: timeoutMinutes, unit: 'MINUTES') {
        def qg = waitForQualityGate()

        result = [
            status: qg.status,
            projectKey: projectKey,
            timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
        ]

        // Try to get detailed conditions
        try {
            def conditions = getQualityGateConditions(projectKey)
            if (conditions) {
                result.conditions = conditions
            }
        } catch (Exception e) {
            echo "Could not fetch quality gate conditions: ${e.message}"
        }
    }

    return result
}

/**
 * Get quality gate conditions from SonarQube API
 */
def getQualityGateConditions(String projectKey) {
    def sonarUrl = env.SONAR_HOST_URL ?: 'http://localhost:9000'
    def sonarToken = env.SONAR_AUTH_TOKEN ?: ''

    try {
        def response = httpRequest(
            url: "${sonarUrl}/api/qualitygates/project_status?projectKey=${projectKey}",
            authentication: sonarToken ? 'sonarqube-token' : null,
            quiet: true,
            validResponseCodes: '200'
        )

        def json = readJSON(text: response.content)
        return json.projectStatus?.conditions ?: []
    } catch (Exception e) {
        return null
    }
}

/**
 * Detect build tool from project files
 */
def detectBuildTool() {
    if (fileExists('pom.xml')) {
        return 'maven'
    } else if (fileExists('build.gradle') || fileExists('build.gradle.kts')) {
        return 'gradle'
    } else if (fileExists('package.json')) {
        return 'node'
    } else if (fileExists('requirements.txt') || fileExists('setup.py') || fileExists('pyproject.toml')) {
        return 'python'
    } else if (fileExists('go.mod')) {
        return 'go'
    }
    return 'generic'
}

/**
 * Build sonar properties string from map
 */
def buildSonarProperties(Map props) {
    if (!props) return ''

    return props.collect { k, v ->
        "-Dsonar.${k}=${v}"
    }.join(' ')
}

/**
 * Write quality gate report to file
 */
def writeQualityGateReport(Map result, String reportsDir) {
    def reportFile = "${reportsDir}/quality-gate.json"

    writeFile(
        file: reportFile,
        text: groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(result))
    )

    echo "Quality gate report: ${reportFile}"
}

/**
 * Standalone SonarQube analysis without quality gate wait
 * Useful for parallel execution
 */
def analyze(Map config = [:]) {
    def projectKey = config.projectKey ?: env.APP_NAME
    def serverName = config.server ?: 'SonarQube'

    echo "=== SonarQube Analysis: ${projectKey} ==="

    runSonarAnalysis(projectKey, serverName, config)

    echo "Analysis submitted to SonarQube"
}

/**
 * Check quality gate status without running analysis
 * Useful after parallel analysis
 */
def check(Map config = [:]) {
    def projectKey = config.projectKey ?: env.APP_NAME
    def serverName = config.server ?: 'SonarQube'
    def failOnQualityGate = config.failOnQualityGate != false
    def waitTimeout = config.waitTimeout ?: 5

    echo "=== Quality Gate Check: ${projectKey} ==="

    def result = waitForQualityGate(projectKey, serverName, waitTimeout)

    if (result.status != 'OK' && result.status != 'PASSED') {
        if (failOnQualityGate) {
            error "Quality gate failed: ${result.status}"
        }
    }

    return result
}
