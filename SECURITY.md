# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

### How to Report

1. **Do NOT** open a public issue for security vulnerabilities
2. Use GitHub's private vulnerability reporting feature (recommended)
3. Or contact the repository maintainer directly via GitHub

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Resolution target**: Depends on severity

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | Yes                |
| < 1.0   | No                 |

## Security Measures in This Project

This project demonstrates security best practices:

### Build Security
- SAST scanning with Semgrep
- SCA scanning with Trivy
- Secrets detection with Gitleaks
- Quality gates with SonarQube

### Supply Chain Security
- SBOM generation (CycloneDX)
- Image signing (Cosign)
- Immutable artifacts (digest-based)

### Deployment Security
- GitOps-based deployments
- Environment promotion via PR
- Audit trail in Git history
- Image signature verification (Kyverno/Sigstore)
- Kubernetes admission control policies

### Access Control
- Role-based access in Jenkins
- Approval workflows for production
- Exception tracking and governance

## Security Considerations for Users

When using this project:

1. **Change default credentials** in `.env`
2. **Secure your Jenkins instance** (authentication, authorization)
3. **Protect signing keys** (use external KMS in production)
4. **Review scanner configurations** for your context
5. **Customize quality gates** to your requirements

## Disclaimer

This project is provided as a reference implementation. Users are responsible for:

- Adapting security controls to their requirements
- Properly securing their deployment environment
- Compliance with their organization's security policies
- Regular security updates and maintenance
