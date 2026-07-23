# Build stage — install only production deps
FROM node:20.18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage — minimal image
FROM node:20.18-alpine
WORKDIR /app

# Non-root user for security — node:alpine images already ship a "node"
# user at UID 1000; reuse it (numeric UID so Kubernetes' runAsNonRoot check
# can verify it without needing to resolve a username inside the container).
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node src/ ./src/
COPY --chown=node:node rds-ca-bundle.pem ./rds-ca-bundle.pem

USER 1000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health/live || exit 1

CMD ["node", "src/index.js"]
