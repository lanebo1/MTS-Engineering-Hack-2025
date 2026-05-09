# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY cmd/trivy-scanner/ ./cmd/trivy-scanner/
COPY internal/ ./internal/
COPY pkg/ ./pkg/

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o trivy-scanner ./cmd/trivy-scanner/

# Runtime stage
FROM alpine:latest

# Install Trivy and additional tools
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -S trivygroup && adduser -S trivyuser -G trivygroup

# Create directories for cache and reports
RUN mkdir -p /opt/trivy/cache /opt/trivy/reports /opt/trivy/scripts
RUN chown -R trivyuser:trivygroup /opt/trivy

# Copy custom scripts
COPY docker/scripts/ /opt/trivy/scripts/
RUN chmod +x /opt/trivy/scripts/*.sh

# Set working directory
WORKDIR /opt/trivy

# Copy the binary
COPY --from=builder /app/trivy-scanner .

# Switch to non-root user
USER trivyuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Default command
CMD ["./trivy-scanner"]
