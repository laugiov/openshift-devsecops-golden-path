# Contributing

Thank you for your interest in contributing to the OpenShift DevSecOps Golden Path.

## Code of Conduct

Be respectful, constructive, and professional in all interactions.

## How to Contribute

### Reporting Issues

1. Check existing issues to avoid duplicates
2. Use the issue template if available
3. Provide:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Docker version, etc.)

### Submitting Changes

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Run tests and linters: `make lint test`
5. Commit with a clear message
6. Submit a pull request

### Commit Messages

Follow conventional commits format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:
```
feat(shared-library): add support for Gradle builds
fix(quality-gate): handle SonarQube timeout gracefully
docs(readme): clarify prerequisites section
```

### Pull Request Guidelines

- Keep PRs focused and reasonably sized
- Update documentation if needed
- Add tests for new functionality
- Ensure CI passes before requesting review
- Respond to review feedback promptly

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/openshift-devsecops-golden-path.git
cd openshift-devsecops-golden-path

# Set up local environment
make setup

# Start services
make up

# Verify everything works
make health
```

## Testing

### Running Tests Locally

```bash
# Quick validation (no Docker required)
make demo-e2e

# Just unit tests
make demo-quick

# All tests including Groovy
make test

# Linting only
make lint

# Security scans (requires tools installed)
make scan-all
```

### Continuous Integration

This repository uses GitHub Actions for CI. Every PR triggers:

1. **Unit Tests** - demo-service Jest tests with coverage
2. **Security Scans** - Gitleaks (secrets), Trivy (vulnerabilities)
3. **Validation** - YAML linting, Groovy syntax check
4. **Docker Build** - Verify image builds correctly
5. **Documentation** - Check for broken links and required docs

To run the same checks locally before pushing:

```bash
# Run all CI checks locally
make demo-e2e

# Or run individual checks
cd demo-service && npm test                           # Unit tests
cd jenkins-shared-library && ./gradlew compileGroovy  # Groovy syntax
yamllint -d relaxed gitops/                          # YAML validation
```

### Testing Jenkins Shared Library

For shared library changes, test locally using:

1. Gradle compilation check: `cd jenkins-shared-library && ./gradlew compileGroovy`
2. Spock unit tests (requires Jenkins mocking): `./gradlew test`
3. Local Jenkins instance with the library configured

## Documentation

- Keep documentation up to date with code changes
- Use clear, concise language
- Include examples where helpful
- Follow existing documentation style

## Questions?

Open an issue with the "question" label for any clarifications needed.
