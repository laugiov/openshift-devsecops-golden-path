#!/usr/bin/env groovy

/**
 * Security Scan Step
 *
 * Runs security scans with adapter pattern support.
 * Supports SAST, SCA, secrets detection, and DAST.
 *
 * Usage:
 *   securityScan(type: 'sast', failOnFindings: true)
 *   securityScan(type: 'sca', failOnFindings: true)
 *   securityScan(type: 'secrets', failOnFindings: true)
 *   securityScan(type: 'dast', targetUrl: 'http://app:8080', failOnFindings: true)
 */

def call(Map config = [:]) {
    def scanType = config.type ?: 'sast'
    def failOnFindings = config.failOnFindings != false
    def targetPath = config.targetPath ?: '.'
    def reportsDir = config.reportsDir ?: 'reports'

    echo "=== Security Scan: ${scanType.toUpperCase()} ==="

    // Create reports directory
    sh "mkdir -p ${reportsDir}"

    def result = [:]

    switch (scanType) {
        case 'sast':
            result = runSastScan(targetPath, reportsDir, config)
            break
        case 'sca':
            result = runScaScan(targetPath, reportsDir, config)
            break
        case 'secrets':
            result = runSecretsScan(targetPath, reportsDir, config)
            break
        case 'dast':
            result = runDastScan(reportsDir, config)
            break
        default:
            error "Unknown scan type: ${scanType}. Supported: sast, sca, secrets, dast"
    }

    // Process results
    if (result.findings > 0) {
        echo "SECURITY FINDINGS: ${result.findings} issue(s) detected"
        echo "Report: ${result.reportFile}"

        if (failOnFindings) {
            error "${scanType.toUpperCase()} scan failed with ${result.findings} finding(s)"
        } else {
            echo "WARNING: Findings detected but failOnFindings=false"
        }
    } else {
        echo "PASSED: No security findings"
    }

    return result
}

/**
 * Run SAST scan using adapter pattern
 */
def runSastScan(String targetPath, String reportsDir, Map config) {
    def adapter = config.adapter ?: env.SAST_ADAPTER ?: 'semgrep'
    def reportFile = "${reportsDir}/sast-${adapter}.json"
    def findings = 0

    echo "SAST Adapter: ${adapter}"

    switch (adapter) {
        case 'semgrep':
            findings = runSemgrep(targetPath, reportFile)
            break
        case 'fortify':
            findings = runFortify(targetPath, reportFile, config)
            break
        case 'checkmarx':
            findings = runCheckmarx(targetPath, reportFile, config)
            break
        default:
            error "Unknown SAST adapter: ${adapter}"
    }

    return [findings: findings, reportFile: reportFile, adapter: adapter]
}

/**
 * Run SCA scan using adapter pattern
 */
def runScaScan(String targetPath, String reportsDir, Map config) {
    def adapter = config.adapter ?: env.SCA_ADAPTER ?: 'trivy'
    def reportFile = "${reportsDir}/sca-${adapter}.json"
    def findings = 0

    echo "SCA Adapter: ${adapter}"

    switch (adapter) {
        case 'trivy':
            findings = runTrivy(targetPath, reportFile, config)
            break
        case 'grype':
            findings = runGrype(targetPath, reportFile)
            break
        case 'snyk':
            findings = runSnyk(targetPath, reportFile, config)
            break
        default:
            error "Unknown SCA adapter: ${adapter}"
    }

    return [findings: findings, reportFile: reportFile, adapter: adapter]
}

/**
 * Run secrets scan using adapter pattern
 */
def runSecretsScan(String targetPath, String reportsDir, Map config) {
    def adapter = config.adapter ?: env.SECRETS_ADAPTER ?: 'gitleaks'
    def reportFile = "${reportsDir}/secrets-${adapter}.json"
    def findings = 0

    echo "Secrets Adapter: ${adapter}"

    switch (adapter) {
        case 'gitleaks':
            findings = runGitleaks(targetPath, reportFile)
            break
        case 'trufflehog':
            findings = runTrufflehog(targetPath, reportFile)
            break
        default:
            error "Unknown secrets adapter: ${adapter}"
    }

    return [findings: findings, reportFile: reportFile, adapter: adapter]
}

// =============================================================================
// SAST Adapters
// =============================================================================

def runSemgrep(String targetPath, String reportFile) {
    def exitCode = sh(
        script: """
            if command -v semgrep &> /dev/null; then
                semgrep scan \
                    --config=auto \
                    --json \
                    --output ${reportFile} \
                    ${targetPath} || true
            else
                docker run --rm \
                    -v \$(pwd):/src \
                    returntocorp/semgrep:latest \
                    semgrep scan \
                        --config=auto \
                        --json \
                        --output /src/${reportFile} \
                        /src/${targetPath} || true
            fi
        """,
        returnStatus: true
    )

    return countSemgrepFindings(reportFile)
}

def countSemgrepFindings(String reportFile) {
    try {
        def count = sh(
            script: "jq '.results | length' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

def runFortify(String targetPath, String reportFile, Map config) {
    // Fortify requires specific configuration
    def fortifyUrl = config.fortifyUrl ?: env.FORTIFY_URL
    def fortifyToken = config.fortifyToken ?: env.FORTIFY_TOKEN
    def fortifyProjectId = config.fortifyProjectId ?: env.FORTIFY_PROJECT_ID

    if (!fortifyUrl) {
        error "Fortify requires 'fortifyUrl' configuration or FORTIFY_URL environment variable"
    }
    if (!fortifyToken) {
        error "Fortify requires 'fortifyToken' configuration or FORTIFY_TOKEN environment variable"
    }
    if (!fortifyProjectId) {
        error "Fortify requires 'fortifyProjectId' configuration or FORTIFY_PROJECT_ID environment variable"
    }

    echo "Running Fortify SAST scan..."
    echo "Fortify URL: ${fortifyUrl}"
    echo "Project ID: ${fortifyProjectId}"

    // Fortify SSC integration using REST API
    withCredentials([string(credentialsId: fortifyToken, variable: 'FORTIFY_AUTH_TOKEN')]) {
        def exitCode = sh(
            script: """
                # Package source for upload
                zip -r source-package.zip ${targetPath} -x "*.git*" -x "node_modules/*" -x "vendor/*"

                # Upload to Fortify SSC and trigger scan
                curl -X POST "${fortifyUrl}/api/v1/cloudjobs/scanRequests" \
                    -H "Authorization: FortifyToken \${FORTIFY_AUTH_TOKEN}" \
                    -H "Content-Type: multipart/form-data" \
                    -F "zipFile=@source-package.zip" \
                    -F "projectVersionId=${fortifyProjectId}" \
                    -o ${reportFile} \
                    --fail --silent --show-error

                rm -f source-package.zip
            """,
            returnStatus: true
        )

        if (exitCode != 0) {
            error "Fortify scan failed. Check Fortify SSC configuration and connectivity."
        }
    }

    return countFortifyFindings(reportFile)
}

def countFortifyFindings(String reportFile) {
    try {
        def count = sh(
            script: "jq '[.data[]? | select(.severity == \"Critical\" or .severity == \"High\")] | length' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

def runCheckmarx(String targetPath, String reportFile, Map config) {
    def checkmarxUrl = config.checkmarxUrl ?: env.CHECKMARX_URL
    def checkmarxCredentialsId = config.checkmarxCredentialsId ?: 'checkmarx-credentials'
    def checkmarxProjectName = config.checkmarxProjectName ?: env.CHECKMARX_PROJECT_NAME

    if (!checkmarxUrl) {
        error "Checkmarx requires 'checkmarxUrl' configuration or CHECKMARX_URL environment variable"
    }
    if (!checkmarxProjectName) {
        error "Checkmarx requires 'checkmarxProjectName' configuration or CHECKMARX_PROJECT_NAME environment variable"
    }

    echo "Running Checkmarx SAST scan..."
    echo "Checkmarx URL: ${checkmarxUrl}"
    echo "Project: ${checkmarxProjectName}"

    // Checkmarx CxSAST integration
    withCredentials([usernamePassword(
        credentialsId: checkmarxCredentialsId,
        usernameVariable: 'CX_USER',
        passwordVariable: 'CX_PASS'
    )]) {
        def exitCode = sh(
            script: """
                # Package source for upload
                zip -r source-package.zip ${targetPath} -x "*.git*" -x "node_modules/*" -x "vendor/*"

                # Authenticate with Checkmarx
                CX_TOKEN=\$(curl -X POST "${checkmarxUrl}/cxrestapi/auth/identity/connect/token" \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "username=\${CX_USER}&password=\${CX_PASS}&grant_type=password&scope=sast_rest_api&client_id=resource_owner_client&client_secret=014DF517-39D1-4453-B7B3-9930C563627C" \
                    --fail --silent | jq -r '.access_token')

                if [ -z "\$CX_TOKEN" ] || [ "\$CX_TOKEN" = "null" ]; then
                    echo "Failed to authenticate with Checkmarx"
                    exit 1
                fi

                # Create and start scan
                curl -X POST "${checkmarxUrl}/cxrestapi/sast/scans" \
                    -H "Authorization: Bearer \$CX_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d '{"projectId": 0, "isIncremental": false, "isPublic": true, "forceScan": true}' \
                    -o ${reportFile} \
                    --fail --silent --show-error

                rm -f source-package.zip
            """,
            returnStatus: true
        )

        if (exitCode != 0) {
            error "Checkmarx scan failed. Check Checkmarx configuration and connectivity."
        }
    }

    return countCheckmarxFindings(reportFile)
}

def countCheckmarxFindings(String reportFile) {
    try {
        def count = sh(
            script: "jq '.highSeverity + .mediumSeverity' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

// =============================================================================
// SCA Adapters
// =============================================================================

def runTrivy(String targetPath, String reportFile, Map config) {
    def severities = config.severities ?: 'CRITICAL,HIGH'

    def exitCode = sh(
        script: """
            if command -v trivy &> /dev/null; then
                trivy fs \
                    --format json \
                    --output ${reportFile} \
                    --severity ${severities} \
                    ${targetPath}
            else
                docker run --rm \
                    -v \$(pwd):/src \
                    aquasec/trivy:latest \
                    fs \
                        --format json \
                        --output /src/${reportFile} \
                        --severity ${severities} \
                        /src/${targetPath}
            fi
        """,
        returnStatus: true
    )

    return countTrivyFindings(reportFile)
}

def countTrivyFindings(String reportFile) {
    try {
        def count = sh(
            script: """
                jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0' ${reportFile} 2>/dev/null || echo 0
            """,
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

def runGrype(String targetPath, String reportFile) {
    def exitCode = sh(
        script: """
            if command -v grype &> /dev/null; then
                grype ${targetPath} \
                    --output json \
                    --file ${reportFile}
            else
                docker run --rm \
                    -v \$(pwd):/src \
                    anchore/grype:latest \
                    /src/${targetPath} \
                        --output json \
                        --file /src/${reportFile}
            fi
        """,
        returnStatus: true
    )

    return countGrypeFindings(reportFile)
}

def countGrypeFindings(String reportFile) {
    try {
        def count = sh(
            script: "jq '.matches | length' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

def runSnyk(String targetPath, String reportFile, Map config) {
    def snykToken = config.snykToken ?: env.SNYK_TOKEN

    if (!snykToken) {
        error "Snyk requires snykToken configuration or SNYK_TOKEN environment variable"
    }

    sh """
        if command -v snyk &> /dev/null; then
            snyk test --json > ${reportFile} || true
        else
            docker run --rm \
                -e SNYK_TOKEN=${snykToken} \
                -v \$(pwd):/src \
                snyk/snyk:latest \
                test --json > ${reportFile} || true
        fi
    """

    return countSnykFindings(reportFile)
}

def countSnykFindings(String reportFile) {
    try {
        def count = sh(
            script: "jq '.vulnerabilities | length' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

// =============================================================================
// Secrets Adapters
// =============================================================================

def runGitleaks(String targetPath, String reportFile) {
    def configArgs = ""
    if (fileExists("${targetPath}/.gitleaks.toml")) {
        configArgs = "--config ${targetPath}/.gitleaks.toml"
    }

    def exitCode = sh(
        script: """
            if command -v gitleaks &> /dev/null; then
                gitleaks detect \
                    --source ${targetPath} \
                    --report-format json \
                    --report-path ${reportFile} \
                    --no-git \
                    ${configArgs} || true
            else
                docker run --rm \
                    -v \$(pwd):/src \
                    zricethezav/gitleaks:latest \
                    detect \
                        --source /src/${targetPath} \
                        --report-format json \
                        --report-path /src/${reportFile} \
                        --no-git || true
            fi
        """,
        returnStatus: true
    )

    // Gitleaks returns 1 when findings exist, 0 when clean
    return countGitleaksFindings(reportFile)
}

def countGitleaksFindings(String reportFile) {
    try {
        if (!fileExists(reportFile)) {
            return 0
        }
        def count = sh(
            script: "jq 'length' ${reportFile} 2>/dev/null || echo 0",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

def runTrufflehog(String targetPath, String reportFile) {
    sh """
        if command -v trufflehog &> /dev/null; then
            trufflehog filesystem ${targetPath} --json > ${reportFile} 2>&1 || true
        else
            docker run --rm \
                -v \$(pwd):/src \
                trufflesecurity/trufflehog:latest \
                filesystem /src/${targetPath} --json > ${reportFile} 2>&1 || true
        fi
    """

    return countTrufflehogFindings(reportFile)
}

def countTrufflehogFindings(String reportFile) {
    try {
        if (!fileExists(reportFile)) {
            return 0
        }
        // TruffleHog outputs one JSON object per line
        def count = sh(
            script: "wc -l < ${reportFile} | tr -d ' '",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}

// =============================================================================
// DAST Adapters (Dynamic Application Security Testing)
// =============================================================================

/**
 * Run DAST scan using adapter pattern
 *
 * DAST requires a running application to test against.
 * Typically run after deploying to a test environment.
 *
 * @param reportsDir Directory for scan reports
 * @param config Configuration including targetUrl, adapter, etc.
 */
def runDastScan(String reportsDir, Map config) {
    def adapter = config.adapter ?: env.DAST_ADAPTER ?: 'zap'
    def targetUrl = config.targetUrl ?: env.DAST_TARGET_URL
    def reportFile = "${reportsDir}/dast-${adapter}.json"
    def findings = 0

    if (!targetUrl) {
        error "DAST scan requires 'targetUrl' parameter or DAST_TARGET_URL environment variable"
    }

    echo "DAST Adapter: ${adapter}"
    echo "Target URL: ${targetUrl}"

    switch (adapter) {
        case 'zap':
            findings = runZap(targetUrl, reportFile, config)
            break
        case 'nuclei':
            findings = runNuclei(targetUrl, reportFile, config)
            break
        default:
            error "Unknown DAST adapter: ${adapter}. Supported: zap, nuclei"
    }

    return [findings: findings, reportFile: reportFile, adapter: adapter, targetUrl: targetUrl]
}

/**
 * Run OWASP ZAP baseline scan
 *
 * ZAP is the industry standard for DAST scanning.
 * Uses baseline scan for CI/CD (fast, non-invasive).
 */
def runZap(String targetUrl, String reportFile, Map config) {
    def scanType = config.zapScanType ?: 'baseline'  // baseline, full-scan, api-scan
    def configFile = config.zapConfig ?: ''
    def riskThreshold = config.riskThreshold ?: 'Medium'  // High, Medium, Low

    echo "ZAP scan type: ${scanType}"

    def zapImage = 'ghcr.io/zaproxy/zaproxy:stable'
    def zapArgs = ""

    if (configFile && fileExists(configFile)) {
        zapArgs += "-c /zap/wrk/${configFile} "
    }

    // Convert report to JSON for consistent parsing
    def jsonReport = reportFile
    def htmlReport = reportFile.replace('.json', '.html')

    def exitCode = sh(
        script: """
            docker run --rm \
                --network host \
                -v \$(pwd):/zap/wrk:rw \
                ${zapImage} \
                zap-${scanType}.py \
                    -t ${targetUrl} \
                    -J ${jsonReport} \
                    -r ${htmlReport} \
                    ${zapArgs} \
                    -I || true
        """,
        returnStatus: true
    )

    // ZAP returns exit codes based on risk level found
    // 0 = pass, 1 = warnings, 2 = failures
    echo "ZAP exit code: ${exitCode}"

    return countZapFindings(jsonReport, riskThreshold)
}

def countZapFindings(String reportFile, String riskThreshold) {
    try {
        if (!fileExists(reportFile)) {
            return 0
        }

        // Map risk levels to numeric values for comparison
        def riskLevels = ['Informational': 0, 'Low': 1, 'Medium': 2, 'High': 3]
        def minRisk = riskLevels[riskThreshold] ?: 2

        // Count alerts at or above threshold
        def count = sh(
            script: """
                jq '[.site[].alerts[] | select(
                    (.riskcode | tonumber) >= ${minRisk}
                )] | length' ${reportFile} 2>/dev/null || echo 0
            """,
            returnStdout: true
        ).trim().toInteger()

        return count
    } catch (Exception e) {
        echo "Warning: Could not parse ZAP report: ${e.message}"
        return 0
    }
}

/**
 * Run Nuclei vulnerability scanner
 *
 * Nuclei is a fast, template-based vulnerability scanner.
 * Good for specific vulnerability checks and API testing.
 */
def runNuclei(String targetUrl, String reportFile, Map config) {
    def templates = config.nucleiTemplates ?: 'cves,vulnerabilities,misconfiguration'
    def severity = config.severity ?: 'medium,high,critical'
    def rateLimitRps = config.rateLimitRps ?: 50

    echo "Nuclei templates: ${templates}"
    echo "Severity filter: ${severity}"

    def exitCode = sh(
        script: """
            if command -v nuclei &> /dev/null; then
                nuclei \
                    -target ${targetUrl} \
                    -t ${templates} \
                    -severity ${severity} \
                    -rate-limit ${rateLimitRps} \
                    -json-export ${reportFile} \
                    -silent || true
            else
                docker run --rm \
                    --network host \
                    -v \$(pwd):/output \
                    projectdiscovery/nuclei:latest \
                    -target ${targetUrl} \
                    -t ${templates} \
                    -severity ${severity} \
                    -rate-limit ${rateLimitRps} \
                    -json-export /output/${reportFile} \
                    -silent || true
            fi
        """,
        returnStatus: true
    )

    return countNucleiFindings(reportFile)
}

def countNucleiFindings(String reportFile) {
    try {
        if (!fileExists(reportFile)) {
            return 0
        }
        // Nuclei outputs one JSON object per line
        def count = sh(
            script: "wc -l < ${reportFile} | tr -d ' '",
            returnStdout: true
        ).trim().toInteger()
        return count
    } catch (Exception e) {
        return 0
    }
}
