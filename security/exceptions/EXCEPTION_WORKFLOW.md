# Security Exception Workflow

This document describes the process for requesting, approving, and tracking security exceptions.

## When to Request an Exception

Request an exception when:

- A security gate blocks deployment but business requires immediate action
- A vulnerability cannot be remediated within standard SLA
- A legacy system requires temporary non-compliance
- A false positive requires time to investigate

**Do NOT use exceptions to:**
- Bypass security permanently
- Avoid fixing known vulnerabilities
- Skip required approvals

## Exception Process

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  1. Request     │────▶│  2. Review      │────▶│  3. Approval    │
│  Create PR with │     │  Security team  │     │  Merge PR with  │
│  exception doc  │     │  assesses risk  │     │  approval       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  6. Close       │◀────│  5. Monitor     │◀────│  4. Implement   │
│  Remove or      │     │  Track during   │     │  Apply          │
│  renew          │     │  exception      │     │  compensating   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Step 1: Create Exception Request

1. Copy the [exception template](exception-template.md)
2. Fill in all required fields
3. Save as `EXC-XXX-short-description.md` in `security/exceptions/`
4. Create a pull request

### Required Information

- **Summary**: One-sentence description
- **Justification**: Why the exception is needed
- **Risk assessment**: Impact if exploited
- **Compensating controls**: Mitigations in place
- **Remediation plan**: How and when it will be fixed
- **Expiration date**: Maximum 90 days

## Step 2: Security Review

Security team will:

1. Assess the risk level
2. Evaluate compensating controls
3. Verify remediation plan is realistic
4. Request additional information if needed

### Review SLA

| Risk Level | Review Time |
|------------|-------------|
| Critical   | 4 hours     |
| High       | 1 business day |
| Medium     | 3 business days |
| Low        | 5 business days |

## Step 3: Approval

Approval authority by risk level:

| Risk Level | Approver |
|------------|----------|
| Critical   | CISO + VP Engineering |
| High       | Security Lead + Engineering Manager |
| Medium     | Security Team Member |
| Low        | Security Team Member |

Approval is recorded via PR approval and merge.

## Step 4: Implement Compensating Controls

Before the exception is active:

1. Implement all stated compensating controls
2. Enable additional monitoring if required
3. Document control implementation

## Step 5: Monitor

During the exception period:

- Security team reviews status weekly
- Remediation progress is tracked
- Any incidents are linked to the exception

## Step 6: Close or Renew

At expiration:

### If Remediated
1. Verify the fix is in place
2. Remove or archive the exception document
3. Close any related tracking issues

### If Renewal Needed
1. Create a new exception request (new PR)
2. Explain why original timeline was not met
3. Provide updated remediation plan
4. Maximum 2 renewals (then escalation required)

## Exception Limits

| Constraint | Limit |
|------------|-------|
| Maximum duration | 90 days |
| Maximum renewals | 2 |
| Critical exceptions in production | 0 (requires escalation) |

## Audit Trail

All exceptions are tracked in Git:

- Creation: PR opened
- Approval: PR approved and merged
- Modification: Commits to exception file
- Closure: File removed or archived

This provides complete audit history for compliance reviews.

## Escalation

Escalate to CISO if:

- Exception renewal denied but business still blocked
- Critical vulnerability requires production exception
- Exception request rejected but team disagrees
- Compensating controls cannot be implemented

## Examples

See [examples/](examples/) for sample exception requests.
