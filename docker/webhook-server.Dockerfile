# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY cmd/webhook-server/ ./cmd/webhook-server/
COPY internal/ ./internal/
COPY pkg/ ./pkg/

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o webhook-server ./cmd/webhook-server/

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates curl

# Copy the binary
COPY --from=builder /app/webhook-server /usr/local/bin/webhook-server

# Copy policies
COPY policies/ /opt/webhook/policies/

# Create config directory
RUN mkdir -p /opt/webhook/config

# Create non-root user
RUN adduser -D -s /bin/sh -u 1000 webhook
USER webhook
WORKDIR /home/webhook

EXPOSE 8443 8080

CMD ["/usr/local/bin/webhook-server"]

