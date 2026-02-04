# Enterprise Security Scanner Integration

This document describes how to integrate enterprise SAST scanners (Fortify, Checkmarx) into the golden path pipeline.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Pipeline                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   Semgrep    │    │   Fortify    │    │  Checkmarx   │          │
│  │  (default)   │    │  (adapter)   │    │  (adapter)   │          │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘          │
│         │                   │                   │                   │
│         └───────────────────┴───────────────────┘                   │
│                             │                                        │
│                    ┌────────▼────────┐                              │
│                    │  SARIF Output   │                              │
│                    │  (standardized) │                              │
│                    └────────┬────────┘                              │
│                             │                                        │
│                    ┌────────▼────────┐                              │
│                    │  Gate Decision  │                              │
│                    │  (pass/fail)    │                              │
│                    └─────────────────┘                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Principles

1. **Adapter Pattern**: Each scanner has an adapter that normalizes output to SARIF
2. **Pluggable**: Switch scanners without changing pipeline logic
3. **Mock Mode**: Test pipeline integration without scanner licenses
4. **Gate Decision**: Standardized pass/fail based on configurable thresholds

## Supported Scanners

| Scanner | Adapter | Mock Support | Output Format |
|---------|---------|--------------|---------------|
| Semgrep | Built-in | N/A (free) | SARIF |
| Fortify SCA | `fortify-adapter.sh` | Yes | SARIF |
| Checkmarx | `checkmarx-adapter.sh` | Yes | SARIF |

## Configuration

### Environment Variables

#### Fortify

| Variable | Required | Description |
|----------|----------|-------------|
| `FORTIFY_SSC_URL` | Yes* | Fortify SSC server URL |
| `FORTIFY_TOKEN` | Yes* | Authentication token |
| `FORTIFY_PROJECT` | No | Project name (default: app name) |
| `FORTIFY_VERSION` | No | Application version |
| `FORTIFY_MOCK_MODE` | No | Set to "true" for testing |

*Not required in mock mode

#### Checkmarx

| Variable | Required | Description |
|----------|----------|-------------|
| `CX_BASE_URL` | Yes* | Checkmarx server URL |
| `CX_CLIENT_ID` | Yes* | OAuth client ID or username |
| `CX_CLIENT_SECRET` | Yes* | OAuth secret or password |
| `CX_TENANT` | CxOne only | Tenant name for CxOne |
| `CX_PROJECT` | No | Project name |
| `CX_BRANCH` | No | Branch to scan |
| `CX_MOCK_MODE` | No | Set to "true" for testing |

*Not required in mock mode

#### Gate Thresholds

| Variable | Default | Description |
|----------|---------|-------------|
| `FAIL_ON_CRITICAL` | true | Fail pipeline on Critical findings |
| `FAIL_ON_HIGH` | true | Fail pipeline on High findings |
| `SEVERITY_THRESHOLD` | Low | Minimum severity to report |

## Usage

### Jenkins Pipeline

```groovy
// Use default scanner (Semgrep)
securityScan(type: 'sast')

// Use Fortify
securityScan(type: 'sast', scanner: 'fortify')

// Use Checkmarx
securityScan(type: 'sast', scanner: 'checkmarx')

// Mock mode for testing
securityScan(type: 'sast', scanner: 'fortify', mockMode: true)
```

### GitLab CI

```yaml
variables:
  SAST_SCANNER: fortify  # or checkmarx, semgrep
  FORTIFY_MOCK_MODE: "true"  # for testing

security:sast:
  script:
    - ./scripts/scanners/run-sast.sh
```

### Direct Execution

```bash
# Fortify with mock mode
FORTIFY_MOCK_MODE=true ./scripts/scanners/adapters/fortify-adapter.sh . ./reports

# Checkmarx with real credentials
CX_BASE_URL=https://cx.example.com \
CX_CLIENT_ID=myapp \
CX_CLIENT_SECRET=secret \
./scripts/scanners/adapters/checkmarx-adapter.sh . ./reports
```

## Output Format (SARIF)

All adapters produce SARIF 2.1.0 output with scanner-specific properties:

```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [{
    "tool": {
      "driver": {
        "name": "Scanner Name",
        "version": "X.Y.Z",
        "rules": [...]
      }
    },
    "results": [{
      "ruleId": "CWE-XXX",
      "level": "error",
      "message": { "text": "..." },
      "locations": [...],
      "properties": {
        "scanner-severity": "High",
        "scanner-specific-field": "value"
      }
    }]
  }]
}
```

## Summary Report

Each scan generates a summary JSON alongside the SARIF report:

```json
{
  "scanner": "fortify",
  "timestamp": "2024-01-15T10:30:00Z",
  "project": "demo-service",
  "findings": {
    "critical": 0,
    "high": 2,
    "medium": 5,
    "low": 10,
    "total": 17
  },
  "threshold": {
    "failOnCritical": true,
    "failOnHigh": true
  },
  "reportFile": "sast-fortify.sarif.json"
}
```

## Gate Decision Logic

```
IF FAIL_ON_CRITICAL == true AND critical_count > 0:
    FAIL("Critical findings detected")

IF FAIL_ON_HIGH == true AND high_count > 0:
    FAIL("High findings detected")

PASS("Security gate passed")
```

## Integration with Enterprise Scanners

### Fortify SSC Integration

1. **Prerequisites**:
   - Fortify SCA installed (sourceanalyzer)
   - Access to Fortify SSC server
   - API token or credentials

2. **Scan Flow**:
   ```
   sourceanalyzer -clean
        ↓
   sourceanalyzer (translation)
        ↓
   sourceanalyzer -scan (analysis)
        ↓
   Upload to SSC / Convert to SARIF
        ↓
   Parse results
        ↓
   Gate decision
   ```

3. **Configuration**:
   ```bash
   export FORTIFY_SSC_URL="https://fortify.example.com/ssc"
   export FORTIFY_TOKEN="your-token"
   export FORTIFY_PROJECT="my-app"
   export FORTIFY_VERSION="1.0.0"
   ```

### Checkmarx Integration

Supports both Checkmarx One (SaaS) and CxSAST (on-premise).

1. **Checkmarx One (SaaS)**:
   ```bash
   export CX_BASE_URL="https://ast.checkmarx.net"
   export CX_TENANT="your-tenant"
   export CX_CLIENT_ID="your-client-id"
   export CX_CLIENT_SECRET="your-client-secret"
   ```

2. **CxSAST (On-Premise)**:
   ```bash
   export CX_BASE_URL="https://checkmarx.example.com"
   export CX_CLIENT_ID="username"
   export CX_CLIENT_SECRET="password"
   ```

## Mock Mode for Testing

Mock mode generates realistic SARIF reports without requiring scanner licenses:

```bash
# Fortify mock
FORTIFY_MOCK_MODE=true ./scripts/scanners/adapters/fortify-adapter.sh

# Checkmarx mock
CX_MOCK_MODE=true ./scripts/scanners/adapters/checkmarx-adapter.sh
```

Mock reports include:
- Realistic vulnerability types (SQL Injection, XSS, etc.)
- Proper SARIF structure
- Scanner-specific properties
- Configurable severity distribution

## Adding a New Scanner

To add a new enterprise scanner:

1. Create adapter script in `scripts/scanners/adapters/`:
   ```bash
   #!/bin/bash
   # my-scanner-adapter.sh

   source "$(dirname "$0")/../common.sh"

   my_scanner_scan() {
       local target_path=$1
       local output_dir=$2

       # Run scanner
       # Convert to SARIF
       # Generate summary
       # Evaluate gate
   }
   ```

2. Implement required functions:
   - `generate_mock_report()` - For testing
   - `parse_sarif_report()` - Extract severity counts
   - `evaluate_gate()` - Pass/fail decision

3. Register in `run-sast.sh`:
   ```bash
   case "$SAST_SCANNER" in
       my-scanner)
           source "$SCRIPT_DIR/adapters/my-scanner-adapter.sh"
           my_scanner_scan "$TARGET" "$OUTPUT_DIR"
           ;;
   esac
   ```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Scanner not found" | Tool not installed | Install scanner or use mock mode |
| "Authentication failed" | Invalid credentials | Check token/credentials |
| "Timeout" | Large codebase | Increase timeout or exclude paths |
| "SARIF conversion failed" | Missing converter | Install fortifycli or use API |

### Debug Mode

Enable verbose output:

```bash
DEBUG=true ./scripts/scanners/adapters/fortify-adapter.sh . ./reports
```

### Logs

Scanner logs are written to:
- `reports/scanner.log` - Execution log
- `reports/sast-*.sarif.json` - Full SARIF report
- `reports/*-summary.json` - Summary with gate decision

## Security Considerations

1. **Credentials**: Never hardcode credentials. Use CI/CD secrets.
2. **Network**: Scanners may need outbound access to license servers.
3. **Permissions**: Scanner service accounts should have minimal permissions.
4. **Audit**: All scans are logged with timestamps and results.

## References

- [SARIF Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [Fortify Documentation](https://www.microfocus.com/documentation/fortify/)
- [Checkmarx Documentation](https://checkmarx.atlassian.net/wiki/spaces/KC/overview)
