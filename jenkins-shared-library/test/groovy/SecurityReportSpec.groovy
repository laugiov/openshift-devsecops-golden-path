package groovy

import spock.lang.Specification
import spock.lang.Unroll
import org.acme.SecurityReport
import org.acme.SecurityReport.ScanResult

/**
 * Unit tests for SecurityReport class
 *
 * Tests the aggregation and reporting logic for security scan results.
 */
class SecurityReportSpec extends Specification {

    def report

    def setup() {
        report = new SecurityReport()
        report.appName = 'test-app'
        report.buildNumber = '42'
        report.timestamp = '2024-01-15T10:00:00Z'
    }

    // =========================================================================
    // ScanResult tests
    // =========================================================================

    def "ScanResult defaults to passed with zero findings"() {
        given:
        def result = new ScanResult()

        expect:
        result.findings == 0
        result.criticalCount == 0
        result.highCount == 0
        result.passed == true
    }

    def "ScanResult can be converted to Map"() {
        given:
        def result = new ScanResult()
        result.type = 'sast'
        result.adapter = 'semgrep'
        result.findings = 5
        result.criticalCount = 1
        result.highCount = 2
        result.passed = false
        result.reportFile = 'reports/sast.json'

        when:
        def map = result.toMap()

        then:
        map.type == 'sast'
        map.adapter == 'semgrep'
        map.findings == 5
        map.criticalCount == 1
        map.highCount == 2
        map.passed == false
        map.reportFile == 'reports/sast.json'
    }

    // =========================================================================
    // SecurityReport aggregation tests
    // =========================================================================

    def "getTotalFindings returns 0 for empty report"() {
        expect:
        report.getTotalFindings() == 0
    }

    def "getTotalFindings sums findings from all scans"() {
        given:
        def sast = new ScanResult(type: 'sast', findings: 3)
        def sca = new ScanResult(type: 'sca', findings: 5)
        def secrets = new ScanResult(type: 'secrets', findings: 0)

        when:
        report.addScanResult('sast', sast)
        report.addScanResult('sca', sca)
        report.addScanResult('secrets', secrets)

        then:
        report.getTotalFindings() == 8
    }

    def "getCriticalFindings sums critical counts"() {
        given:
        def sast = new ScanResult(type: 'sast', criticalCount: 2)
        def sca = new ScanResult(type: 'sca', criticalCount: 1)

        when:
        report.addScanResult('sast', sast)
        report.addScanResult('sca', sca)

        then:
        report.getCriticalFindings() == 3
    }

    def "getHighFindings sums high counts"() {
        given:
        def sast = new ScanResult(type: 'sast', highCount: 4)
        def sca = new ScanResult(type: 'sca', highCount: 3)

        when:
        report.addScanResult('sast', sast)
        report.addScanResult('sca', sca)

        then:
        report.getHighFindings() == 7
    }

    def "hasFindings returns false when all scans are clean"() {
        given:
        report.addScanResult('sast', new ScanResult(type: 'sast', findings: 0))
        report.addScanResult('sca', new ScanResult(type: 'sca', findings: 0))

        expect:
        report.hasFindings() == false
    }

    def "hasFindings returns true when any scan has findings"() {
        given:
        report.addScanResult('sast', new ScanResult(type: 'sast', findings: 0))
        report.addScanResult('sca', new ScanResult(type: 'sca', findings: 1))

        expect:
        report.hasFindings() == true
    }

    def "allPassed returns true when all scans passed"() {
        given:
        report.addScanResult('sast', new ScanResult(type: 'sast', passed: true))
        report.addScanResult('sca', new ScanResult(type: 'sca', passed: true))

        expect:
        report.allPassed() == true
    }

    def "allPassed returns false when any scan failed"() {
        given:
        report.addScanResult('sast', new ScanResult(type: 'sast', passed: true))
        report.addScanResult('sca', new ScanResult(type: 'sca', passed: false))

        expect:
        report.allPassed() == false
    }

    // =========================================================================
    // Report conversion tests
    // =========================================================================

    def "toMap includes all report data"() {
        given:
        def sast = new ScanResult(type: 'sast', findings: 2, criticalCount: 1, passed: false)
        report.addScanResult('sast', sast)

        when:
        def map = report.toMap()

        then:
        map.appName == 'test-app'
        map.buildNumber == '42'
        map.timestamp == '2024-01-15T10:00:00Z'
        map.totalFindings == 2
        map.criticalFindings == 1
        map.allPassed == false
        map.scans.containsKey('sast')
    }

    def "getSummary generates readable output"() {
        given:
        def sast = new ScanResult(type: 'sast', findings: 2, passed: false)
        def sca = new ScanResult(type: 'sca', findings: 0, passed: true)
        report.addScanResult('sast', sast)
        report.addScanResult('sca', sca)

        when:
        def summary = report.getSummary()

        then:
        summary.contains('test-app')
        summary.contains('Build: 42')
        summary.contains('SAST: FAILED (2 findings)')
        summary.contains('SCA: PASSED (0 findings)')
        summary.contains('Status: FAILED')
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    def "report handles null values gracefully"() {
        given:
        def result = new ScanResult()
        result.type = null
        result.adapter = null

        when:
        report.addScanResult('test', result)
        def map = report.toMap()

        then:
        noExceptionThrown()
        map.scans.containsKey('test')
    }

    @Unroll
    def "report correctly handles #scenario"() {
        given:
        scans.each { name, result ->
            report.addScanResult(name, result)
        }

        expect:
        report.getTotalFindings() == expectedTotal
        report.allPassed() == expectedPassed

        where:
        scenario                    | scans                                                          | expectedTotal | expectedPassed
        'single passed scan'        | ['sast': new ScanResult(findings: 0, passed: true)]           | 0             | true
        'single failed scan'        | ['sast': new ScanResult(findings: 3, passed: false)]          | 3             | false
        'multiple passed scans'     | ['sast': new ScanResult(passed: true), 'sca': new ScanResult(passed: true)] | 0 | true
        'mixed results'             | ['sast': new ScanResult(findings: 2, passed: false), 'sca': new ScanResult(findings: 0, passed: true)] | 2 | false
    }
}
