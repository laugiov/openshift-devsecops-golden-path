package org.acme

/**
 * Security Report Class
 *
 * Aggregates and normalizes security scan results from multiple sources.
 */
class SecurityReport implements Serializable {

    String appName
    String buildNumber
    String timestamp
    Map<String, ScanResult> scans = [:]

    /**
     * Add scan result to report
     */
    void addScanResult(String scanType, ScanResult result) {
        scans[scanType] = result
    }

    /**
     * Get total findings count
     */
    int getTotalFindings() {
        return scans.values().sum { it.findings } ?: 0
    }

    /**
     * Get critical findings count
     */
    int getCriticalFindings() {
        return scans.values().sum { it.criticalCount } ?: 0
    }

    /**
     * Get high findings count
     */
    int getHighFindings() {
        return scans.values().sum { it.highCount } ?: 0
    }

    /**
     * Check if any scan has findings
     */
    boolean hasFindings() {
        return getTotalFindings() > 0
    }

    /**
     * Check if all scans passed
     */
    boolean allPassed() {
        return scans.values().every { it.passed }
    }

    /**
     * Convert to Map for serialization
     */
    Map toMap() {
        return [
            appName: appName,
            buildNumber: buildNumber,
            timestamp: timestamp,
            totalFindings: getTotalFindings(),
            criticalFindings: getCriticalFindings(),
            highFindings: getHighFindings(),
            allPassed: allPassed(),
            scans: scans.collectEntries { k, v -> [k, v.toMap()] }
        ]
    }

    /**
     * Generate summary string
     */
    String getSummary() {
        def sb = new StringBuilder()
        sb.append("Security Report for ${appName}\n")
        sb.append("Build: ${buildNumber}\n")
        sb.append("Timestamp: ${timestamp}\n")
        sb.append("-" * 40 + "\n")

        scans.each { type, result ->
            sb.append("${type.toUpperCase()}: ${result.passed ? 'PASSED' : 'FAILED'} (${result.findings} findings)\n")
        }

        sb.append("-" * 40 + "\n")
        sb.append("Total: ${getTotalFindings()} findings (${getCriticalFindings()} critical, ${getHighFindings()} high)\n")
        sb.append("Status: ${allPassed() ? 'ALL PASSED' : 'FAILED'}\n")

        return sb.toString()
    }

    /**
     * Inner class for individual scan results
     */
    static class ScanResult implements Serializable {
        String type
        String adapter
        int findings = 0
        int criticalCount = 0
        int highCount = 0
        int mediumCount = 0
        int lowCount = 0
        boolean passed = true
        String reportFile
        String timestamp

        Map toMap() {
            return [
                type: type,
                adapter: adapter,
                findings: findings,
                criticalCount: criticalCount,
                highCount: highCount,
                mediumCount: mediumCount,
                lowCount: lowCount,
                passed: passed,
                reportFile: reportFile,
                timestamp: timestamp
            ]
        }
    }
}
