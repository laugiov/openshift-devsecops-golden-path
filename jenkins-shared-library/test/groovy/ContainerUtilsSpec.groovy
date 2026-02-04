package groovy

import spock.lang.Specification
import spock.lang.Unroll

/**
 * Unit tests for containerUtils shared library step
 *
 * These tests verify the core utility functions without requiring
 * a running Jenkins instance.
 */
class ContainerUtilsSpec extends Specification {

    def containerUtils

    def setup() {
        // Load the containerUtils script
        def binding = new Binding()
        def shell = new GroovyShell(binding)

        // Mock Jenkins pipeline methods
        binding.sh = { Map args ->
            if (args.script.contains('command -v podman')) {
                return args.returnStatus ? 1 : ''  // podman not available
            }
            if (args.script.contains('command -v docker')) {
                return args.returnStatus ? 0 : ''  // docker available
            }
            if (args.script.contains('inspect --format')) {
                return 'sha256:' + 'a' * 64
            }
            return ''
        }

        binding.echo = { msg -> println msg }
        binding.error = { msg -> throw new RuntimeException(msg) }

        containerUtils = shell.evaluate(new File('vars/containerUtils.groovy'))
    }

    // =========================================================================
    // isValidDigest tests
    // =========================================================================

    @Unroll
    def "isValidDigest returns #expected for digest '#digest'"() {
        expect:
        containerUtils.isValidDigest(digest) == expected

        where:
        digest                                                              | expected
        'sha256:' + 'a' * 64                                               | true
        'sha256:' + 'f' * 64                                               | true
        'sha256:' + '0' * 64                                               | true
        'sha256:abc123'                                                     | false  // too short
        'sha256:' + 'a' * 65                                               | false  // too long
        'sha256:' + 'g' * 64                                               | false  // invalid char
        'md5:' + 'a' * 64                                                  | false  // wrong algorithm
        null                                                                | false
        ''                                                                  | false
    }

    // =========================================================================
    // imageWithDigest tests
    // =========================================================================

    def "imageWithDigest creates correct reference"() {
        given:
        def imageName = 'registry.io/myapp'
        def digest = 'sha256:' + 'a' * 64

        when:
        def result = containerUtils.imageWithDigest(imageName, digest)

        then:
        result == "registry.io/myapp@sha256:${'a' * 64}"
    }

    def "imageWithDigest strips existing tag"() {
        given:
        def imageName = 'registry.io/myapp:v1.0.0'
        def digest = 'sha256:' + 'b' * 64

        when:
        def result = containerUtils.imageWithDigest(imageName, digest)

        then:
        result == "registry.io/myapp@sha256:${'b' * 64}"
    }

    def "imageWithDigest throws on invalid digest"() {
        given:
        def imageName = 'registry.io/myapp'
        def invalidDigest = 'invalid'

        when:
        containerUtils.imageWithDigest(imageName, invalidDigest)

        then:
        thrown(RuntimeException)
    }

    // =========================================================================
    // extractRegistry tests
    // =========================================================================

    @Unroll
    def "extractRegistry returns '#expected' for image '#imageName'"() {
        expect:
        containerUtils.extractRegistry(imageName) == expected

        where:
        imageName                                  | expected
        'registry.io/org/app'                      | 'registry.io'
        'gcr.io/project/image'                     | 'gcr.io'
        'localhost:5000/app'                       | 'localhost:5000'
        '123456789.dkr.ecr.us-east-1.amazonaws.com/app' | '123456789.dkr.ecr.us-east-1.amazonaws.com'
        'myapp'                                    | 'docker.io'  // Docker Hub default
        'library/nginx'                            | 'docker.io'  // Docker Hub official
        'org/app'                                  | 'docker.io'  // Docker Hub user
    }
}
