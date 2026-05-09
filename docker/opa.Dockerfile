# Dockerfile for OPA Policy Engine Service
FROM alpine:latest

# Install OPA and additional tools
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    && curl -L -o /usr/local/bin/opa https://github.com/open-policy-agent/opa/releases/download/v0.58.0/opa_linux_amd64_static \
    && chmod +x /usr/local/bin/opa \
    && ls -la /usr/local/bin/opa \
    && addgroup -S opagroup \
    && adduser -S opauser -G opagroup \
    && mkdir -p /opt/opa/policies /opt/opa/data /opt/opa/scripts \
    && chown -R opauser:opagroup /opt/opa

# Copy custom scripts
COPY docker/scripts/ /opt/opa/scripts/
RUN chmod +x /opt/opa/scripts/*.sh

# Ensure opauser can access the binary
RUN chown opauser:opagroup /usr/local/bin/opa

# Set working directory
WORKDIR /opt/opa

# Set PATH to include /usr/local/bin
ENV PATH="/usr/local/bin:$PATH"

# Expose OPA API port
EXPOSE 8181

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8181/health || exit 1

# Default command - start OPA server
CMD ["opa", "run", "--server", "--addr", "0.0.0.0:8181", "/opt/opa/policies"]
