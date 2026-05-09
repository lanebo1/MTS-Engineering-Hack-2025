#!/bin/bash
# Test script for Trivy Scanner
# Tests the scanner functionality with sample images

set -e

# Configuration
SCANNER_URL="http://localhost:8080"
TEST_IMAGE="nginx:1.21"  # Known to have some vulnerabilities
OUTPUT_DIR="./test-output"
LOG_FILE="./test-trivy-scanner.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
        return 0
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name"
        return 1
    fi
}

# Setup
setup() {
    log "Setting up test environment"
    mkdir -p "$OUTPUT_DIR"
    rm -f "$LOG_FILE"
}

# Cleanup
cleanup() {
    log "Cleaning up test environment"
    rm -rf "$OUTPUT_DIR"
}

# Test health endpoint
test_health() {
    curl -s -f "$SCANNER_URL/health" > /dev/null
}

# Test readiness endpoint
test_readiness() {
    curl -s -f "$SCANNER_URL/ready" > /dev/null
}

# Test basic scan
test_basic_scan() {
    local response_file="$OUTPUT_DIR/basic_scan.json"

    curl -s -X POST "$SCANNER_URL/api/v1/scan" \
         -H "Content-Type: application/json" \
         -d "{\"image\": \"$TEST_IMAGE\"}" \
         -o "$response_file"

    # Check if response is valid JSON and contains expected fields
    jq -e '.success == true and .image == "'$TEST_IMAGE'" and (.vulnerabilities | length) >= 0' "$response_file" > /dev/null
}

# Test scan with custom parameters
test_custom_scan() {
    local response_file="$OUTPUT_DIR/custom_scan.json"

    curl -s -X POST "$SCANNER_URL/api/v1/scan" \
         -H "Content-Type: application/json" \
         -d "{
           \"image\": \"$TEST_IMAGE\",
           \"scan_types\": [\"os\", \"library\"],
           \"severity_levels\": [\"CRITICAL\", \"HIGH\"],
           \"format\": \"json\"
         }" \
         -o "$response_file"

    # Check if response is valid JSON
    jq -e '.success == true' "$response_file" > /dev/null
}

# Test invalid image
test_invalid_image() {
    local response_file="$OUTPUT_DIR/invalid_scan.json"

    curl -s -X POST "$SCANNER_URL/api/v1/scan" \
         -H "Content-Type: application/json" \
         -d "{\"image\": \"nonexistent:image\"}" \
         -o "$response_file" || true

    # Should return error
    jq -e '.success == false or .error' "$response_file" > /dev/null
}

# Test scan results analysis
analyze_results() {
    local response_file="$OUTPUT_DIR/basic_scan.json"

    if [[ ! -f "$response_file" ]]; then
        log "No scan results to analyze"
        return 1
    fi

    local total_vulns=$(jq -r '.summary.total' "$response_file")
    local critical_vulns=$(jq -r '.summary.critical' "$response_file")
    local high_vulns=$(jq -r '.summary.high' "$response_file")

    log "Scan Results Analysis:"
    log "  Total vulnerabilities: $total_vulns"
    log "  Critical: $critical_vulns"
    log "  High: $high_vulns"
    log "  Image: $TEST_IMAGE"

    # Show top 5 most severe vulnerabilities
    log "Top vulnerabilities:"
    jq -r '.vulnerabilities[] | select(.severity == "CRITICAL" or .severity == "HIGH") | "\(.severity): \(.id) in \(.package) (\(.cvss_score))"' "$response_file" | head -5 | while read line; do
        log "  $line"
    done
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    setup

    log "Starting Trivy Scanner tests"
    log "Scanner URL: $SCANNER_URL"
    log "Test image: $TEST_IMAGE"

    # Run tests
    tests=(
        "Health endpoint: test_health"
        "Readiness endpoint: test_readiness"
        "Basic scan: test_basic_scan"
        "Custom scan: test_custom_scan"
        "Invalid image handling: test_invalid_image"
    )

    for test in "${tests[@]}"; do
        IFS=':' read -r test_name test_func <<< "$test"
        ((total_tests++))

        if ! run_test "$test_name" "$test_func"; then
            ((failed_tests++))
        fi
    done

    # Analyze results if basic scan succeeded
    if [[ -f "$OUTPUT_DIR/basic_scan.json" ]]; then
        log "Analyzing scan results..."
        analyze_results
    fi

    # Summary
    log "Test Summary: $((total_tests - failed_tests))/$total_tests tests passed"

    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}$failed_tests test(s) failed${NC}"
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
    "analyze")
        analyze_results
        ;;
    *)
        main
        ;;
esac
