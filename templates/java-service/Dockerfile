# Multi-stage Dockerfile for Spring Boot
# Optimized for security and fast builds

# ============================================
# Stage 1: Build
# ============================================
FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /workspace

# Copy Maven wrapper and pom.xml for dependency caching
COPY mvnw pom.xml ./
COPY .mvn .mvn

# Download dependencies (cached if pom.xml unchanged)
RUN ./mvnw dependency:go-offline -B

# Copy source code
COPY src src

# Build application with layered jar
RUN ./mvnw package -DskipTests -B && \
    mkdir -p target/extracted && \
    java -Djarmode=layertools -jar target/*.jar extract --destination target/extracted

# ============================================
# Stage 2: Runtime
# ============================================
FROM eclipse-temurin:21-jre-alpine AS runtime

# Security: Run as non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy layered jar for optimal caching
COPY --from=builder --chown=appuser:appgroup /workspace/target/extracted/dependencies/ ./
COPY --from=builder --chown=appuser:appgroup /workspace/target/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=appuser:appgroup /workspace/target/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=appuser:appgroup /workspace/target/extracted/application/ ./

# Security hardening
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Expose port
EXPOSE 8080

# JVM options for containers
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Start application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
