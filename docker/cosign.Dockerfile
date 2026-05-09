# Dockerfile for Cosign Container Image Signer
FROM cgr.dev/chainguard/cosign:v2.4.0

# Install additional tools and create user/directory structure
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    && rm -rf /var/cache/apk/* \
    && addgroup -S cosigngroup && adduser -S cosignuser -G cosigngroup \
    && mkdir -p /opt/cosign/keys /opt/cosign/cache /opt/cosign/scripts /opt/cosign/logs \
    && chown -R cosignuser:cosigngroup /opt/cosign

# Copy and configure custom scripts
COPY docker/scripts/cosign-* /opt/cosign/scripts/
RUN chmod +x /opt/cosign/scripts/*.sh

# Set working directory
WORKDIR /opt/cosign

# Switch to non-root user
USER cosignuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD cosign version || exit 1

# Default command
CMD ["cosign", "version"]
