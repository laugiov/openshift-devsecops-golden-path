# {{SERVICE_NAME}} Dockerfile
# Multi-stage build for minimal production image

# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies first (better caching)
COPY package*.json ./
RUN npm ci --omit=dev

# Copy source code
COPY . .

# Build if needed (uncomment for TypeScript/compiled projects)
# RUN npm run build

# Production stage
FROM node:20-alpine AS production

# Security: run as non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D appuser

WORKDIR /app

# Copy only production dependencies and built code
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json ./
COPY --from=builder --chown=appuser:appgroup /app/src ./src

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:{{SERVICE_PORT}}/health || exit 1

# Expose port
EXPOSE {{SERVICE_PORT}}

# Start application
CMD ["node", "src/index.js"]
