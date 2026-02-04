# Jenkins Shared Library Tests

Unit tests for the Golden Path Jenkins Shared Library.

## Running Tests

### Prerequisites

- Java 11+
- Gradle 7+ (or use wrapper)

### Run All Tests

```bash
cd jenkins-shared-library
./gradlew test
```

### Run Tests with Verbose Output

```bash
./gradlew testVerbose
```

### View Test Report

After running tests, open:
```
build/reports/tests/test/index.html
```

## Test Structure

```
test/
└── groovy/
    ├── ContainerUtilsSpec.groovy   # Tests for containerUtils.groovy
    └── GoldenPipelineSpec.groovy   # Tests for goldenPipeline.groovy
```

## Test Framework

Tests use [Spock Framework](https://spockframework.org/) which provides:
- BDD-style test syntax
- Data-driven testing with `where:` blocks
- Clear given/when/then structure
- Excellent mock support

## What's Tested

### ContainerUtilsSpec

| Function | Test Cases |
|----------|------------|
| `isValidDigest` | Valid SHA256, invalid lengths, invalid characters, null |
| `imageWithDigest` | Basic reference, strip existing tag, invalid digest |
| `extractRegistry` | Various registry formats, Docker Hub default |

### GoldenPipelineSpec

| Function | Test Cases |
|----------|------------|
| `validateConfig` | Required appName, format validation, buildTool options |
| `validateEmergencyMode` | Required fields, secrets bypass blocked |
| `shouldFailOnGate` | Normal mode, emergency bypass behavior |

## Adding New Tests

1. Create a new `*Spec.groovy` file in `test/groovy/`
2. Extend `spock.lang.Specification`
3. Mock Jenkins pipeline methods in `setup()`
4. Write tests using given/when/then syntax

Example:
```groovy
class MyStepSpec extends Specification {

    def "my function does something"() {
        given:
        def input = 'test'

        when:
        def result = myFunction(input)

        then:
        result == 'expected'
    }
}
```

## CI Integration

Tests run automatically in the pipeline:

```groovy
stage('Test Shared Library') {
    steps {
        dir('jenkins-shared-library') {
            sh './gradlew test'
        }
    }
    post {
        always {
            junit 'jenkins-shared-library/build/test-results/**/*.xml'
        }
    }
}
```

## Known Limitations

- Tests don't cover full Jenkins pipeline DSL (requires Jenkins test harness)
- Integration tests require a running Jenkins instance
- Some steps need mocked external services (SonarQube, registry)

For full integration testing, consider:
- [Jenkins Test Harness](https://github.com/jenkinsci/jenkins-test-harness)
- [Jenkins Pipeline Unit](https://github.com/jenkinsci/JenkinsPipelineUnit)
