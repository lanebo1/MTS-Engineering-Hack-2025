#!/bin/bash
# Test script for Webhook Server
# Tests the admission webhook server functionality

set -e

# Configuration
WEBHOOK_BINARY="./cmd/webhook-server/main.go"
SERVER_URL="http://localhost:8080"
TEST_IMAGE="nginx:1.21"
OUTPUT_DIR="./webhook-test-output"
LOG_FILE="./test-webhook-server.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Test function
run_test() {
    local test_name="$1"
    local test_cmd="$2"

    log "Running test: $test_name"
    if eval "$test_cmd"; then
        echo -e "${GREEN}✓ PASS:${NC} $test_name"
        echo "<testcase name=\"$test_name\" classname=\"Webhook_Server\" time=\"0.001\"/>" >> "$JUNIT_FILE"
        return 0
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name"
        echo "<testcase name=\"$test_name\" classname=\"Webhook_Server\" time=\"0.001\"><failure message=\"Test failed\"/></testcase>" >> "$JUNIT_FILE"
        return 1
    fi
}

# Setup
setup() {
    log "Setting up webhook server test environment"
    mkdir -p "$OUTPUT_DIR"
    rm -f "$LOG_FILE"

    # Initialize JUnit XML file
    JUNIT_FILE="$OUTPUT_DIR/junit-report.xml"
    cat > "$JUNIT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Webhook Server Tests">
  <testsuite name="Webhook_Server">
EOF

    # Check if Go is available
    if ! command -v go &> /dev/null; then
        echo -e "${RED}Error: Go not found. Please install Go first.${NC}"
        exit 1
    fi

    # Build webhook server if needed
    if [[ ! -f "./webhook-server" ]]; then
        log "Building webhook server..."
        go build -o webhook-server "$WEBHOOK_BINARY"
    fi
}

# Cleanup
cleanup() {
    log "Cleaning up webhook server test environment"

    # Stop webhook server if running
    if [[ -n "$SERVER_PID" ]]; then
        log "Stopping webhook server (PID: $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    # Finalize JUnit XML file
    if [[ -f "$JUNIT_FILE" ]]; then
        cat >> "$JUNIT_FILE" << EOF
  </testsuite>
</testsuites>
EOF
    fi

    rm -rf "$OUTPUT_DIR"
    rm -f webhook-server
}

# Start webhook server in background
start_webhook_server() {
    log "Starting webhook server on port 8080 (HTTP mode for testing)..."

    # Create temporary config files
    mkdir -p /tmp/webhook-config

    # Start server in HTTP mode (no TLS for testing)
    ./webhook-server \
        --port=8080 \
        --host=127.0.0.1 \
        --log-level=debug \
        > webhook-server.log 2>&1 &
    SERVER_PID=$!

    log "Webhook server started with PID: $SERVER_PID"

    # Wait for server to be ready
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if curl -s -f "$SERVER_URL/ready" > /dev/null 2>&1; then
            log "Webhook server is ready"
            return 0
        fi
        sleep 1
        ((retries--))
    done

    log "Webhook server failed to start"
    return 1
}

# Test health endpoint
test_health_endpoint() {
    local response_file="$OUTPUT_DIR/health_response.json"

    curl -s -X GET "$SERVER_URL/health" \
         -H "Content-Type: application/json" \
         -o "$response_file"

    # Check if response is valid JSON and contains expected fields
    jq -e '.status == "healthy" and .service == "admission-webhook"' "$response_file" > /dev/null
}

# Test readiness endpoint
test_readiness_endpoint() {
    local response_file="$OUTPUT_DIR/ready_response.json"

    curl -s -X GET "$SERVER_URL/ready" \
         -H "Content-Type: application/json" \
         -o "$response_file"

    # Check if response is valid JSON and contains expected fields
    jq -e '.status == "ready" and .service == "admission-webhook"' "$response_file" > /dev/null
}

# Test admission webhook endpoint
test_admission_endpoint() {
    local response_file="$OUTPUT_DIR/admission_response.json"

    # Create admission request payload
    cat > "$OUTPUT_DIR/admission_request.json" << EOF
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "test-uid-12345",
    "kind": {
      "group": "",
      "version": "v1",
      "kind": "Pod"
    },
    "resource": {
      "group": "",
      "version": "v1",
      "resource": "pods"
    },
    "name": "test-pod",
    "namespace": "default",
    "operation": "CREATE",
    "object": {
      "apiVersion": "v1",
      "kind": "Pod",
      "metadata": {
        "name": "test-pod",
        "namespace": "default"
      },
      "spec": {
        "containers": [
          {
            "name": "test-container",
            "image": "$TEST_IMAGE",
            "ports": [
              {
                "containerPort": 80
              }
            ]
          }
        ]
      }
    }
  }
}
EOF

    curl -s -X POST "$SERVER_URL/admission" \
         -H "Content-Type: application/json" \
         -d @"$OUTPUT_DIR/admission_request.json" \
         -o "$response_file"

    # Check if response is valid AdmissionReview
    jq -e '.apiVersion == "admission.k8s.io/v1" and .kind == "AdmissionReview" and .response' "$response_file" > /dev/null
}

# Test invalid admission request
test_invalid_admission() {
    local response_file="$OUTPUT_DIR/invalid_admission_response.json"

    curl -s -X POST "$SERVER_URL/admission" \
         -H "Content-Type: application/json" \
         -d '{"invalid": "json"}' \
         -o "$response_file" || true

    # Should return error status
    jq -e '.response.allowed == false or .error' "$response_file" > /dev/null 2>/dev/null || true
}

# Test server logs for errors
test_server_logs() {
    # Check if server logs contain any fatal errors
    if grep -q "FATAL\|panic\|error.*starting" webhook-server.log; then
        log "Found errors in server logs"
        return 1
    fi

    # Check if server processed requests
    if ! grep -q "POST /admission\|GET /health\|GET /ready" webhook-server.log; then
        log "Server did not process expected requests"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    setup

    # Start webhook server
    if ! start_webhook_server; then
        echo -e "${RED}Failed to start webhook server${NC}"
        cleanup
        exit 1
    fi

    log "Starting webhook server tests"
    log "Server URL: $SERVER_URL"
    log "Test image: $TEST_IMAGE"

    # Run tests
    tests=(
        "Health endpoint: test_health_endpoint"
        "Readiness endpoint: test_readiness_endpoint"
        "Admission webhook endpoint: test_admission_endpoint"
        "Invalid admission request handling: test_invalid_admission"
        "Server logs validation: test_server_logs"
    )

    for test in "${tests[@]}"; do
        IFS=':' read -r test_name test_func <<< "$test"
        ((total_tests++))

        if ! run_test "$test_name" "$test_func"; then
            ((failed_tests++))
        fi
    done

    # Summary
    log "Test Summary: $((total_tests - failed_tests))/$total_tests tests passed"

    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}All webhook server tests passed!${NC}"
        cleanup
        exit 0
    else
        echo -e "${RED}$failed_tests webhook server test(s) failed${NC}"
        echo -e "${YELLOW}Server logs:${NC}"
        tail -20 webhook-server.log
        cleanup
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "setup")
        setup
        ;;
    "cleanup")
        cleanup
        ;;
    "start-server")
        setup
        start_webhook_server
        echo "Server started. Press Ctrl+C to stop."
        wait
        ;;
    *)
        main
        ;;
esac
