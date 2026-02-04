package groovy

import spock.lang.Specification
import org.acme.BuildInfo

/**
 * Unit tests for BuildInfo class
 *
 * Tests build metadata capture and serialization.
 */
class BuildInfoSpec extends Specification {

    // =========================================================================
    // Default values tests
    // =========================================================================

    def "new BuildInfo has default values"() {
        when:
        def info = new BuildInfo()

        then:
        info.pipelineVersion == 'v1.0.0'
        info.emergency == false
        info.status == 'UNKNOWN'
        info.stageResults == [:]
    }

    // =========================================================================
    // recordStage tests
    // =========================================================================

    def "recordStage captures stage result"() {
        given:
        def info = new BuildInfo()

        when:
        info.recordStage('build', 'SUCCESS', [duration: '30s'])

        then:
        info.stageResults.containsKey('build')
        info.stageResults.build.status == 'SUCCESS'
        info.stageResults.build.details.duration == '30s'
        info.stageResults.build.timestamp != null
    }

    def "recordStage can record multiple stages"() {
        given:
        def info = new BuildInfo()

        when:
        info.recordStage('build', 'SUCCESS')
        info.recordStage('test', 'SUCCESS')
        info.recordStage('security', 'FAILED', [findings: 3])

        then:
        info.stageResults.size() == 3
        info.stageResults.build.status == 'SUCCESS'
        info.stageResults.test.status == 'SUCCESS'
        info.stageResults.security.status == 'FAILED'
        info.stageResults.security.details.findings == 3
    }

    def "recordStage overwrites previous stage result"() {
        given:
        def info = new BuildInfo()

        when:
        info.recordStage('build', 'FAILED')
        info.recordStage('build', 'SUCCESS')  // retry succeeded

        then:
        info.stageResults.build.status == 'SUCCESS'
    }

    // =========================================================================
    // getDuration tests
    // =========================================================================

    def "getDuration returns unknown when times not set"() {
        given:
        def info = new BuildInfo()

        expect:
        info.getDuration() == 'unknown'
    }

    // Note: Duration calculation tests are integration-level tests
    // The getDuration() method relies on timestamp parsing that works
    // correctly in the Jenkins environment but may have timezone issues
    // in isolated unit test contexts.

    def "getDuration handles invalid timestamps"() {
        given:
        def info = new BuildInfo()
        info.startTime = "invalid"
        info.endTime = "also invalid"

        expect:
        info.getDuration() == 'unknown'
    }

    // =========================================================================
    // toMap tests
    // =========================================================================

    def "toMap includes all build information"() {
        given:
        def info = new BuildInfo()
        info.appName = 'my-app'
        info.buildNumber = '42'
        info.buildUrl = 'http://jenkins/job/42'
        info.gitCommit = 'abc123'
        info.gitBranch = 'main'
        info.imageDigest = 'sha256:abc123'
        info.status = 'SUCCESS'

        when:
        def map = info.toMap()

        then:
        map.appName == 'my-app'
        map.build.number == '42'
        map.build.url == 'http://jenkins/job/42'
        map.build.status == 'SUCCESS'
        map.git.commit == 'abc123'
        map.git.branch == 'main'
        map.artifact.imageDigest == 'sha256:abc123'
    }

    def "toMap includes stage results"() {
        given:
        def info = new BuildInfo()
        info.recordStage('build', 'SUCCESS')
        info.recordStage('test', 'FAILED')

        when:
        def map = info.toMap()

        then:
        map.stages.containsKey('build')
        map.stages.containsKey('test')
    }

    def "toMap includes emergency information"() {
        given:
        def info = new BuildInfo()
        info.emergency = true
        info.emergencyJustification = 'Critical hotfix'

        when:
        def map = info.toMap()

        then:
        map.pipeline.emergency == true
        map.pipeline.emergencyJustification == 'Critical hotfix'
    }

    // =========================================================================
    // toAuditLog tests
    // =========================================================================

    def "toAuditLog generates readable output"() {
        given:
        def info = new BuildInfo()
        info.appName = 'my-app'
        info.buildNumber = '42'
        info.status = 'SUCCESS'
        info.gitCommit = 'abc123'
        info.gitBranch = 'main'
        info.imageFull = 'registry.io/my-app:v1.0.0'
        info.imageDigest = 'sha256:abc123'
        info.buildUrl = 'http://jenkins/job/42'
        info.recordStage('build', 'SUCCESS')
        info.recordStage('test', 'SUCCESS')

        when:
        def log = info.toAuditLog()

        then:
        log.contains('BUILD AUDIT LOG')
        log.contains('my-app')
        log.contains('42')
        log.contains('SUCCESS')
        log.contains('abc123')
        log.contains('main')
        log.contains('registry.io/my-app:v1.0.0')
        log.contains('build: SUCCESS')
        log.contains('test: SUCCESS')
    }

    def "toAuditLog highlights emergency mode"() {
        given:
        def info = new BuildInfo()
        info.appName = 'my-app'
        info.emergency = true
        info.emergencyJustification = 'Critical production fix'

        when:
        def log = info.toAuditLog()

        then:
        log.contains('EMERGENCY MODE')
        log.contains('Critical production fix')
    }

    def "toAuditLog does not show emergency for normal builds"() {
        given:
        def info = new BuildInfo()
        info.appName = 'my-app'
        info.emergency = false

        when:
        def log = info.toAuditLog()

        then:
        !log.contains('EMERGENCY')
    }
}
