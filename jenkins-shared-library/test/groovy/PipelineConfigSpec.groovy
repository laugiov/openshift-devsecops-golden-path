package groovy

import spock.lang.Specification
import spock.lang.Unroll
import org.acme.PipelineConfig

/**
 * Unit tests for PipelineConfig class
 *
 * Tests configuration validation and defaults.
 */
class PipelineConfigSpec extends Specification {

    // =========================================================================
    // Default values tests
    // =========================================================================

    def "new PipelineConfig has sensible defaults"() {
        when:
        def config = new PipelineConfig()

        then:
        config.buildTool == 'node'
        config.registry == 'localhost:5000'
        config.enableSast == true
        config.enableSca == true
        config.enableSecrets == true
        config.failOnSecurityFindings == true
        config.enableSbom == true
        config.enableSigning == true
        config.enableGitOps == true
        config.targetEnv == 'dev'
        config.dockerfile == 'Dockerfile'
        config.buildContext == '.'
        config.emergency == false
    }

    // =========================================================================
    // fromMap tests
    // =========================================================================

    def "fromMap creates config with provided values"() {
        given:
        def map = [
            appName: 'my-app',
            buildTool: 'maven',
            registry: 'gcr.io/my-project',
            enableSast: false,
            targetEnv: 'prod'
        ]

        when:
        def config = PipelineConfig.fromMap(map)

        then:
        config.appName == 'my-app'
        config.buildTool == 'maven'
        config.registry == 'gcr.io/my-project'
        config.enableSast == false
        config.targetEnv == 'prod'
    }

    def "fromMap ignores unknown properties"() {
        given:
        def map = [
            appName: 'my-app',
            unknownProperty: 'should be ignored'
        ]

        when:
        def config = PipelineConfig.fromMap(map)

        then:
        noExceptionThrown()
        config.appName == 'my-app'
    }

    def "fromMap preserves defaults for unspecified properties"() {
        given:
        def map = [appName: 'my-app']

        when:
        def config = PipelineConfig.fromMap(map)

        then:
        config.buildTool == 'node'  // default preserved
        config.enableSast == true    // default preserved
    }

    // =========================================================================
    // Validation tests
    // =========================================================================

    def "validate returns error when appName is missing"() {
        given:
        def config = new PipelineConfig()

        when:
        def errors = config.validate()

        then:
        errors.any { it.contains('appName is required') }
    }

    @Unroll
    def "validate accepts valid appName '#appName'"() {
        given:
        def config = new PipelineConfig()
        config.appName = appName

        when:
        def errors = config.validate()

        then:
        !errors.any { it.contains('appName must be') }

        where:
        appName << ['my-app', 'app123', 'a', 'test-service-v2']
    }

    @Unroll
    def "validate rejects invalid appName '#appName'"() {
        given:
        def config = new PipelineConfig()
        config.appName = appName

        when:
        def errors = config.validate()

        then:
        errors.any { it.contains('lowercase alphanumeric') }

        where:
        appName << ['My-App', 'app_name', 'APP', 'app name']
    }

    @Unroll
    def "validate accepts valid buildTool '#buildTool'"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'test'
        config.buildTool = buildTool

        when:
        def errors = config.validate()

        then:
        !errors.any { it.contains('buildTool') }

        where:
        buildTool << ['node', 'maven', 'gradle', 'python', 'go']
    }

    def "validate rejects invalid buildTool"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'test'
        config.buildTool = 'rust'

        when:
        def errors = config.validate()

        then:
        errors.any { it.contains('buildTool must be one of') }
    }

    def "validate requires justification in emergency mode"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'test'
        config.emergency = true

        when:
        def errors = config.validate()

        then:
        errors.any { it.contains('emergencyJustification') }
    }

    def "validate accepts emergency mode with justification"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'test'
        config.emergency = true
        config.emergencyJustification = 'Critical hotfix for production issue'

        when:
        def errors = config.validate()

        then:
        !errors.any { it.contains('emergencyJustification') }
    }

    // =========================================================================
    // isValid tests
    // =========================================================================

    def "isValid returns true for valid config"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'my-app'

        expect:
        config.isValid() == true
    }

    def "isValid returns false for invalid config"() {
        given:
        def config = new PipelineConfig()
        // appName missing

        expect:
        config.isValid() == false
    }

    // =========================================================================
    // toMap tests
    // =========================================================================

    def "toMap includes all properties"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'test-app'
        config.buildTool = 'maven'
        config.emergency = true
        config.emergencyJustification = 'test'

        when:
        def map = config.toMap()

        then:
        map.appName == 'test-app'
        map.buildTool == 'maven'
        map.emergency == true
        map.emergencyJustification == 'test'
        map.containsKey('enableSast')
        map.containsKey('enableSca')
        map.containsKey('enableSbom')
    }

    // =========================================================================
    // toString tests
    // =========================================================================

    def "toString returns readable representation"() {
        given:
        def config = new PipelineConfig()
        config.appName = 'my-app'
        config.buildTool = 'gradle'
        config.registry = 'docker.io'

        when:
        def str = config.toString()

        then:
        str.contains('my-app')
        str.contains('gradle')
        str.contains('docker.io')
    }
}
