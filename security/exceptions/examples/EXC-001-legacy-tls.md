# Exception Request: [EXC-001] Legacy Payment Gateway TLS 1.1

## Status: APPROVED

---

## Summary

Legacy payment gateway integration requires TLS 1.1 support until vendor upgrade completes.

## Affected Systems

| Field | Value |
|-------|-------|
| Service(s) | payment-service |
| Environment(s) | production |
| Component(s) | External payment gateway client |

## Security Finding

| Field | Value |
|-------|-------|
| Finding ID | SCAN-2024-001 |
| Severity | Medium |
| Scanner | Infrastructure security scan |
| Description | TLS 1.1 is deprecated and has known weaknesses |

## Justification

Our payment processor (ACME Payments) requires TLS 1.1 for their legacy API endpoint. They have committed to upgrading to TLS 1.3 by Q2 2024. Switching providers would take 6+ months and impact revenue.

## Risk Assessment

### If Exploited

An attacker performing a man-in-the-middle attack could potentially decrypt payment data in transit. This would require:
- Network position between our service and payment gateway
- Significant computational resources for TLS 1.1 attacks

### Likelihood

| Factor | Assessment |
|--------|------------|
| Exposure | Internet-facing (outbound only) |
| Authentication required | Yes (API keys) |
| User interaction required | No |
| Known exploits | Theoretical (BEAST, etc.) |

### Risk Rating

**Overall Risk: MEDIUM**

## Compensating Controls

- [x] Traffic limited to single payment gateway IP
- [x] Additional network monitoring on payment traffic
- [x] API key rotation every 30 days (vs standard 90)
- [x] Alerting on any TLS downgrade attempts
- [x] Certificate pinning implemented

## Remediation Plan

| Milestone | Target Date | Owner |
|-----------|-------------|-------|
| Vendor confirms TLS 1.3 timeline | 2024-01-15 | Payment team |
| Test TLS 1.3 in staging | 2024-03-01 | Platform team |
| Production migration | 2024-04-15 | Payment team |
| Final fix deployed | 2024-04-30 | Payment team |

## Timeline

| Field | Date |
|-------|------|
| Requested | 2024-01-10 |
| Expires | 2024-04-10 |

## Approvals

| Role | Name | Date | Decision |
|------|------|------|----------|
| Requestor | Jane Developer | 2024-01-10 | Requested |
| Security Reviewer | Security Team | 2024-01-11 | Reviewed |
| Approver | Security Lead | 2024-01-12 | Approved |

---

## For Security Team Use

### Review Notes

Risk accepted given:
- Vendor timeline is credible
- Compensating controls are strong
- Business impact of alternative is significant

Condition: Monthly status update required.

### Monitoring Requirements

- Weekly review of payment traffic logs
- Alert on any anomalous patterns
- Immediate notification if vendor timeline slips

### Renewal History

*No renewals yet*
