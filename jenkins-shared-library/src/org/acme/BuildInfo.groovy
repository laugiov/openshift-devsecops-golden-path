package org.acme

/**
 * Build Information Class
 *
 * Captures and stores build metadata for audit and traceability.
 */
class BuildInfo implements Serializable {

    // Build identifiers
    String appName
    String buildNumber
    String buildUrl
    String jobName

    // Git information
    String gitCommit
    String gitBranch
    String gitUrl

    // Timestamps
    String startTime
    String endTime

    // Artifact information
    String imageTag
    String imageDigest
    String imageFull

    // Pipeline information
    String pipelineVersion = 'v1.0.0'
    boolean emergency = false
    String emergencyJustification = ''

    // Results
    String status = 'UNKNOWN'
    Map<String, Object> stageResults = [:]

    private static final String DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss'Z'"

    /**
     * Record stage result
     */
    void recordStage(String stageName, String status, Map<String, Object> details = [:]) {
        def sdf = new java.text.SimpleDateFormat(DATE_FORMAT)
        sdf.setTimeZone(TimeZone.getTimeZone('UTC'))
        stageResults[stageName] = [
            status: status,
            timestamp: sdf.format(new Date()),
            details: details
        ]
    }

    /**
     * Calculate build duration
     */
    String getDuration() {
        if (!startTime || !endTime) return 'unknown'

        try {
            def sdf = new java.text.SimpleDateFormat(DATE_FORMAT)
            sdf.setTimeZone(TimeZone.getTimeZone('UTC'))
            def start = sdf.parse(startTime)
            def end = sdf.parse(endTime)
            def durationMs = end.time - start.time

            def seconds = ((durationMs / 1000) % 60) as int
            def minutes = ((durationMs / (1000 * 60)) % 60) as int
            def hours = ((durationMs / (1000 * 60 * 60))) as int

            if (hours > 0) {
                return "${hours}h ${minutes}m ${seconds}s"
            } else if (minutes > 0) {
                return "${minutes}m ${seconds}s"
            } else {
                return "${seconds}s"
            }
        } catch (Exception e) {
            return 'unknown'
        }
    }

    /**
     * Convert to Map for JSON serialization
     */
    Map toMap() {
        return [
            appName: appName,
            build: [
                number: buildNumber,
                url: buildUrl,
                jobName: jobName,
                status: status,
                duration: getDuration()
            ],
            git: [
                commit: gitCommit,
                branch: gitBranch,
                url: gitUrl
            ],
            timestamps: [
                start: startTime,
                end: endTime
            ],
            artifact: [
                imageTag: imageTag,
                imageDigest: imageDigest,
                imageFull: imageFull
            ],
            pipeline: [
                version: pipelineVersion,
                emergency: emergency,
                emergencyJustification: emergencyJustification
            ],
            stages: stageResults
        ]
    }

    /**
     * Generate audit log entry
     */
    String toAuditLog() {
        def sb = new StringBuilder()
        sb.append("=== BUILD AUDIT LOG ===\n")
        sb.append("Application: ${appName}\n")
        sb.append("Build: ${buildNumber}\n")
        sb.append("Status: ${status}\n")
        sb.append("Duration: ${getDuration()}\n")
        sb.append("\n")
        sb.append("Git Commit: ${gitCommit}\n")
        sb.append("Git Branch: ${gitBranch}\n")
        sb.append("\n")
        sb.append("Image: ${imageFull}\n")
        sb.append("Digest: ${imageDigest}\n")
        sb.append("\n")

        if (emergency) {
            sb.append("!!! EMERGENCY MODE !!!\n")
            sb.append("Justification: ${emergencyJustification}\n")
            sb.append("\n")
        }

        sb.append("Stage Results:\n")
        stageResults.each { stage, result ->
            sb.append("  ${stage}: ${result.status}\n")
        }

        sb.append("\n")
        sb.append("Pipeline Version: ${pipelineVersion}\n")
        sb.append("Build URL: ${buildUrl}\n")
        sb.append("======================\n")

        return sb.toString()
    }
}
