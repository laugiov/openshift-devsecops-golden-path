package groovy

import spock.lang.Specification
import spock.lang.Unroll

/**
 * Unit tests for goldenPipeline shared library step
 *
 * These tests verify configuration validation and emergency mode logic
 * without requiring a running Jenkins instance.
 */
class GoldenPipelineSpec extends Specification {

    def goldenPipeline
    def capturedErrors = []

    def setup() {
        def binding = new Binding()
        def shell = new GroovyShell(binding)

        // Mock Jenkins pipeline methods
        binding.env = [
            BUILD_NUMBER: '123',
            BUILD_URL: 'http://jenkins/job/test/123',
            GIT_COMMIT: 'abc123',
            GIT_BRANCH: 'main'
        ]
        binding.echo = { msg -> println msg }
        binding.error = { msg ->
            capturedErrors << msg
            throw new RuntimeException(msg)
        }

        // Mock notifySlack
        binding.notifySlack = { Map args -> println "Slack: ${args}" }

        goldenPipeline = shell.evaluate(new File('vars/goldenPipeline.groovy'))
        capturedErrors.clear()
    }

    // =========================================================================
    // validateConfig tests
    // =========================================================================

    def "validateConfig requires appName"() {
        when:
        goldenPipeline.validateConfig([:])

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('appName is required') }
    }

    def "validateConfig validates appName format"() {
        when:
        goldenPipeline.validateConfig([appName: 'Invalid_Name'])

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('lowercase alphanumeric') }
    }

    @Unroll
    def "validateConfig accepts valid appName '#appName'"() {
        when:
        goldenPipeline.validateConfig([appName: appName])

        then:
        noExceptionThrown()

        where:
        appName << ['my-service', 'app123', 'a', 'service-v2']
    }

    def "validateConfig validates buildTool options"() {
        when:
        goldenPipeline.validateConfig([appName: 'test', buildTool: 'invalid'])

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('buildTool must be one of') }
    }

    // =========================================================================
    // Emergency Mode tests
    // =========================================================================

    def "validateEmergencyMode requires justification"() {
        given:
        def config = [
            emergency: true,
            emergencyApprover: 'john.doe',
            emergencyTicket: 'INC-123',
            emergencyBypassGates: ['securityFindings']
        ]

        when:
        goldenPipeline.validateEmergencyMode(config)

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('emergencyJustification') }
    }

    def "validateEmergencyMode requires approver"() {
        given:
        def config = [
            emergency: true,
            emergencyJustification: 'Critical production fix',
            emergencyTicket: 'INC-123',
            emergencyBypassGates: ['securityFindings']
        ]

        when:
        goldenPipeline.validateEmergencyMode(config)

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('emergencyApprover') }
    }

    def "validateEmergencyMode requires ticket"() {
        given:
        def config = [
            emergency: true,
            emergencyJustification: 'Critical production fix',
            emergencyApprover: 'john.doe',
            emergencyBypassGates: ['securityFindings']
        ]

        when:
        goldenPipeline.validateEmergencyMode(config)

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('emergencyTicket') }
    }

    def "validateEmergencyMode blocks secrets bypass"() {
        given:
        def config = [
            emergency: true,
            emergencyJustification: 'Critical production fix',
            emergencyApprover: 'john.doe',
            emergencyTicket: 'INC-123',
            emergencyBypassGates: ['secrets']  // Attempting to bypass secrets
        ]

        when:
        goldenPipeline.validateEmergencyMode(config)

        then:
        thrown(RuntimeException)
        capturedErrors.any { it.contains('secrets') && it.contains('cannot be bypassed') }
    }

    def "validateEmergencyMode accepts valid config"() {
        given:
        def config = [
            emergency: true,
            emergencyJustification: 'Critical production fix for payment processing',
            emergencyApprover: 'john.doe@acme.com',
            emergencyTicket: 'INC-2024-001',
            emergencyBypassGates: ['securityFindings', 'qualityGate']
        ]

        when:
        goldenPipeline.validateEmergencyMode(config)

        then:
        noExceptionThrown()
    }

    // =========================================================================
    // shouldFailOnGate tests
    // =========================================================================

    def "shouldFailOnGate returns true in normal mode"() {
        given:
        def config = [emergency: false]

        expect:
        goldenPipeline.shouldFailOnGate(config, 'securityFindings') == true
        goldenPipeline.shouldFailOnGate(config, 'qualityGate') == true
    }

    def "shouldFailOnGate respects bypass list in emergency mode"() {
        given:
        def config = [
            emergency: true,
            emergencyBypassGates: ['securityFindings']
        ]

        expect:
        goldenPipeline.shouldFailOnGate(config, 'securityFindings') == false  // bypassed
        goldenPipeline.shouldFailOnGate(config, 'qualityGate') == true        // not bypassed
    }
}
