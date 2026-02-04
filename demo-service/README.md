# Demo Service

A minimal Node.js API demonstrating the Golden Path CI/CD pipeline.

## Purpose

This service exists to:
- Provide a buildable artifact for pipeline demonstration
- Generate meaningful security scan results
- Show quality gate integration

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (liveness) |
| GET | `/ready` | Readiness check |
| GET | `/api/info` | Service information |
| POST | `/api/echo` | Echo message back |

## Local Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run tests
npm test

# Run linter
npm run lint
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| PORT | 3000 | Server port |
| NODE_ENV | development | Environment |
| LOG_LEVEL | info | Pino log level |
| APP_VERSION | 1.0.0 | Application version |

## Docker

```bash
# Build image
docker build -t demo-service:local .

# Run container
docker run -p 3000:3000 demo-service:local

# Test
curl http://localhost:3000/health
```
