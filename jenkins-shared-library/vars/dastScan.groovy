/**
 * DAST Scan Pipeline Step
 *
 * Executes OWASP ZAP Dynamic Application Security Testing against a running application.
 *
 * Usage:
 *   dastScan(
 *       targetUrl: 'https://myapp-staging.example.com',
 *       scanType: 'baseline',  // baseline, api, full
 *       failOnHigh: true,
 *       failOnMedium: false
 *   )
 *
 * Requirements:
 *   - Docker available on Jenkins agent
 *   - Target application must be accessible from Jenkins
 */

def call(Map config = [:]) {
    def targetUrl = config.targetUrl ?: env.DAST_TARGET_URL
    def scanType = config.scanType ?: 'baseline'
    def failOnHigh = config.failOnHigh != null ? config.failOnHigh : true
    def failOnMedium = config.failOnMedium != null ? config.failOnMedium : false
    def timeout = config.timeout ?: 30  // minutes
    def mockMode = config.mockMode ?: false

    if (!targetUrl) {
        error "DAST scan requires targetUrl parameter or DAST_TARGET_URL environment variable"
    }

    echo "╔════════════════════════════════════════════╗"
    echo "║           DAST SCAN - OWASP ZAP            ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║  Target: ${targetUrl}"
    echo "║  Scan Type: ${scanType}"
    echo "║  Fail on High: ${failOnHigh}"
    echo "║  Fail on Medium: ${failOnMedium}"
    echo "╚════════════════════════════════════════════╝"

    def reportDir = "${env.WORKSPACE}/reports/dast"
    sh "mkdir -p ${reportDir}"

    def exitCode = 0

    timeout(time: timeout, unit: 'MINUTES') {
        if (mockMode) {
            // Use mock mode for testing
            exitCode = sh(
                script: """
                    export ZAP_MOCK_MODE=true
                    export FAIL_ON_HIGH=${failOnHigh}
                    export FAIL_ON_MEDIUM=${failOnMedium}
                    ./scripts/scanners/dast/zap-scan.sh "${targetUrl}" "${reportDir}" "${scanType}"
                """,
                returnStatus: true
            )
        } else {
            // Run actual ZAP scan
            def zapImage = config.zapImage ?: 'ghcr.io/zaproxy/zaproxy:stable'

            switch (scanType) {
                case 'baseline':
                    exitCode = runBaselineScan(targetUrl, reportDir, zapImage, failOnHigh, failOnMedium)
                    break
                case 'api':
                    def apiSpec = config.apiSpec ?: ''
                    exitCode = runApiScan(targetUrl, reportDir, zapImage, apiSpec, failOnHigh, failOnMedium)
                    break
                case 'full':
                    exitCode = runFullScan(targetUrl, reportDir, zapImage, failOnHigh, failOnMedium)
                    break
                default:
                    error "Unknown scan type: ${scanType}"
            }
        }
    }

    // Archive reports
    archiveArtifacts artifacts: 'reports/dast/**', allowEmptyArchive: true

    // Publish SARIF if plugin available
    try {
        recordIssues(
            tools: [sarif(pattern: 'reports/dast/*.sarif.json')],
            qualityGates: [[threshold: 1, type: 'TOTAL_HIGH', unstable: !failOnHigh]]
        )
    } catch (Exception e) {
        echo "SARIF recording skipped: ${e.message}"
    }

    // Publish HTML report if available
    if (fileExists("${reportDir}/zap-report.html")) {
        publishHTML([
            allowMissing: true,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: reportDir,
            reportFiles: 'zap-report.html',
            reportName: 'OWASP ZAP Report'
        ])
    }

    // Return scan result
    def result = [
        success: (exitCode == 0),
        targetUrl: targetUrl,
        scanType: scanType,
        reportPath: "${reportDir}/dast-zap.sarif.json"
    ]

    // Parse summary if available
    if (fileExists("${reportDir}/zap-summary.json")) {
        def summary = readJSON file: "${reportDir}/zap-summary.json"
        result.findings = summary.findings
    }

    if (exitCode != 0) {
        if (failOnHigh || failOnMedium) {
            error "DAST scan failed security gate"
        } else {
            unstable "DAST scan found security issues"
        }
    }

    return result
}

private int runBaselineScan(String targetUrl, String reportDir, String zapImage, boolean failOnHigh, boolean failOnMedium) {
    return sh(
        script: """
            docker run --rm \\
                -v ${reportDir}:/zap/wrk:rw \\
                -t ${zapImage} \\
                zap-baseline.py \\
                -t "${targetUrl}" \\
                -J zap-report.json \\
                -r zap-report.html \\
                -w zap-report.md \\
                -I
        """,
        returnStatus: true
    )
}

private int runApiScan(String targetUrl, String reportDir, String zapImage, String apiSpec, boolean failOnHigh, boolean failOnMedium) {
    def apiArgs = apiSpec ? "-f openapi -O ${apiSpec}" : ""

    return sh(
        script: """
            docker run --rm \\
                -v ${reportDir}:/zap/wrk:rw \\
                -t ${zapImage} \\
                zap-api-scan.py \\
                -t "${targetUrl}" \\
                -J zap-report.json \\
                -r zap-report.html \\
                ${apiArgs} \\
                -I
        """,
        returnStatus: true
    )
}

private int runFullScan(String targetUrl, String reportDir, String zapImage, boolean failOnHigh, boolean failOnMedium) {
    return sh(
        script: """
            docker run --rm \\
                -v ${reportDir}:/zap/wrk:rw \\
                -t ${zapImage} \\
                zap-full-scan.py \\
                -t "${targetUrl}" \\
                -J zap-report.json \\
                -r zap-report.html \\
                -I
        """,
        returnStatus: true
    )
}
