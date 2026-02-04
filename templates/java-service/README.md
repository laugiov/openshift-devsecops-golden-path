# Java Demo Service

A Spring Boot demo service demonstrating the Golden Path DevSecOps pipeline for Java applications.

## Stack

- Java 21 (LTS)
- Spring Boot 3.2
- Maven
- JUnit 5

## Quick Start

```bash
# Build
./mvnw clean package

# Run
./mvnw spring-boot:run

# Test
./mvnw test
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check |
| `GET /api/ready` | Kubernetes readiness |
| `GET /api/info` | Service information |
| `GET /actuator/prometheus` | Prometheus metrics |

## Build & Deploy

### Local Docker Build

```bash
docker build -t java-demo-service:local .
docker run -p 8080:8080 java-demo-service:local
```

### CI/CD Pipeline

The service uses the Golden Path Jenkins pipeline:

```groovy
goldenPipeline(
    appName: 'java-demo-service',
    buildTool: 'maven'
)
```

## Security

The Docker image is built with:
- Non-root user (UID 1001)
- Minimal base image (Alpine JRE)
- No shell access in production
- Read-only filesystem compatible

## Configuration

Environment variables:
- `JAVA_OPTS` - JVM options (default: container-aware settings)

Spring profiles:
- `default` - Development
- `prod` - Production settings

## SBOM

Software Bill of Materials is generated automatically:
- CycloneDX format
- Available at `target/bom.json` after build
