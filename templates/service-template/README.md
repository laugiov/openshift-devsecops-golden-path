# Service Template

This is the Golden Path template for creating new microservices.

## Usage

Do **not** use this template directly. Run the bootstrap script:

```bash
./scripts/bootstrap-service.sh my-service-name \
  --port 8080 \
  --team "My Team" \
  --email team@acme.com
```

This will:
1. Copy this template to `services/my-service-name/`
2. Replace all placeholders with actual values
3. Generate GitOps configuration in `gitops/`

## Template Structure

```
service-template/
├── helm/              # Helm chart (values replaced by bootstrap)
├── src/               # Node.js application code
├── Dockerfile         # Multi-stage production build
├── Jenkinsfile        # CI/CD pipeline using golden library
└── package.json       # Dependencies
```

## Placeholders

The following placeholders are replaced by `bootstrap-service.sh`:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `__SERVICE_NAME__` | Service name (kebab-case) | `payment-service` |
| `__SERVICE_PORT__` | HTTP port | `3000` |
| `__REGISTRY_URL__` | Container registry | `registry.acme.io` |
| `__TEAM_NAME__` | Team name | `Platform Team` |
| `__TEAM_EMAIL__` | Team email | `platform@acme.com` |

## Customization

After bootstrapping, customize your service:

1. Edit `src/index.js` for business logic
2. Update `helm/values.yaml` for deployment config
3. Modify `Jenkinsfile` for pipeline customization

## Validation

Run `helm lint` on your generated chart:

```bash
helm lint services/my-service-name/helm
```
