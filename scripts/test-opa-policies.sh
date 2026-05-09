#!/bin/bash
# Test script for OPA Security Policies
# Tests all security policies with various scenarios

set -e

# Configuration
POLICIES_DIR="./policies"
TEST_SCENARIOS="$POLICIES_DIR/test_scenarios.json"
OUTPUT_DIR="./test-results"
LOG_FILE="./test-opa-policies.log"
OPA_BINARY="docker run --rm -v $(pwd)/policies:/policies:ro -v $(pwd)/$OUTPUT_DIR:/output openpolicyagent/opa:latest"
JUNIT_FILE="$OUTPUT_DIR/junit-report.xml"

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
run_policy_test() {
    local test_name="$1"
    local policy_file="$2"
    local query="$3"
    local input_data="$4"
    local expected_result="$5"
    local expected_reason="$6"

    log "Running test: $test_name"

    # Create temporary input file
    local input_file="$OUTPUT_DIR/${test_name}_input.json"
    local output_file="$OUTPUT_DIR/${test_name}_output.json"

    echo "$input_data" > "$input_file"

    # Build OPA command
    local opa_cmd="$OPA_BINARY eval --data /policies --input /output/${test_name}_input.json --format json $query"

    # Run OPA evaluation
    if eval "$opa_cmd" 2>/dev/null > "$output_file"; then

        # Parse result
        local actual_result=$(jq -r '.result[0].expressions[0].value' "$output_file")

        if [[ "$actual_result" == "$expected_result" ]]; then
            echo -e "${GREEN}✓ PASS:${NC} $test_name"
            echo "<testcase name=\"$test_name\" classname=\"OPA_Policies\" time=\"0.001\"/>" >> "$JUNIT_FILE"
            return 0
        else
            echo -e "${RED}✗ FAIL:${NC} $test_name"
            echo -e "${RED}  Expected: $expected_result, Got: $actual_result${NC}"
            echo "<testcase name=\"$test_name\" classname=\"OPA_Policies\" time=\"0.001\"><failure message=\"Expected: $expected_result, Got: $actual_result\"/></testcase>" >> "$JUNIT_FILE"
            return 1
        fi
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name (OPA evaluation failed)"
        echo "<testcase name=\"$test_name\" classname=\"OPA_Policies\" time=\"0.001\"><error message=\"OPA evaluation failed\"/></testcase>" >> "$JUNIT_FILE"
        return 1
    fi
}

# Test integration function
run_integration_test() {
    local test_name="$1"
    local input_data="$2"
    local expected_allow="$3"
    local expected_reason="$4"

    log "Running integration test: $test_name"

    # Create temporary input file
    local input_file="$OUTPUT_DIR/${test_name}_input.json"
    local output_file="$OUTPUT_DIR/${test_name}_output.json"

    echo "$input_data" > "$input_file"

    # Run OPA evaluation for container_security
    if $OPA_BINARY eval \
        --data "/policies" \
        --input "/output/${test_name}_input.json" \
        --format json \
        "data.container_security.allow" 2>/dev/null > "$output_file"; then

        local actual_allow=$(jq -r '.result[0].expressions[0].value' "$output_file")

        if [[ "$actual_allow" == "$expected_allow" ]]; then
            echo -e "${GREEN}✓ PASS:${NC} $test_name"

            # If blocked, check reason
            if [[ "$expected_allow" == "false" && -n "$expected_reason" ]]; then
                local reason_output="$OUTPUT_DIR/${test_name}_reason.json"
                $OPA_BINARY eval \
                    --data "/policies" \
                    --input "/output/${test_name}_input.json" \
                    --format json \
                    "data.container_security.reason" 2>/dev/null > "$reason_output"

                local actual_reason=$(jq -r '.result[0].expressions[0].value' "$reason_output")
                if [[ "$actual_reason" == *"$expected_reason"* ]]; then
                    echo -e "${GREEN}  ✓ Reason matches: $actual_reason${NC}"
                else
                    echo -e "${YELLOW}  ⚠ Reason mismatch. Expected: '$expected_reason', Got: '$actual_reason'${NC}"
                fi
            fi

            echo "<testcase name=\"$test_name\" classname=\"OPA_Integration\" time=\"0.001\"/>" >> "$JUNIT_FILE"
            return 0
        else
            echo -e "${RED}✗ FAIL:${NC} $test_name"
            echo -e "${RED}  Expected allow: $expected_allow, Got: $actual_allow${NC}"
            echo "<testcase name=\"$test_name\" classname=\"OPA_Integration\" time=\"0.001\"><failure message=\"Expected allow: $expected_allow, Got: $actual_allow\"/></testcase>" >> "$JUNIT_FILE"
            return 1
        fi
    else
        echo -e "${RED}✗ FAIL:${NC} $test_name (OPA evaluation failed)"
        cat "$output_file"
        echo "<testcase name=\"$test_name\" classname=\"OPA_Integration\" time=\"0.001\"><error message=\"OPA evaluation failed\"/></testcase>" >> "$JUNIT_FILE"
        return 1
    fi
}

# Setup
setup() {
    log "Setting up test environment"

    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker not found. Please install Docker first.${NC}"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR"
    rm -f "$LOG_FILE"

    # Initialize JUnit XML file
    cat > "$JUNIT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="OPA Security Policies Tests">
  <testsuite name="OPA_Policies">
EOF
}

# Cleanup
cleanup() {
    log "Cleaning up test environment"

    # Finalize JUnit XML file
    if [[ -f "$JUNIT_FILE" ]]; then
        cat >> "$JUNIT_FILE" << EOF
  </testsuite>
</testsuites>
EOF
    fi

    rm -rf "$OUTPUT_DIR"
}

# Test policies individually
test_vulnerability_policy() {
    log "Testing vulnerability policy..."

    local failed=0
    local total=0

    # Count total test cases
    total=$(jq '[.test_cases[] | select(.expected.vulnerability_policy_allow != null)] | length' "$TEST_SCENARIOS" 2>/dev/null)
    if [[ $? -ne 0 || -z "$total" ]]; then
        echo -e "${RED}Failed to parse test scenarios${NC}"
        return 1
    fi

    # Run tests one by one
    for i in $(seq 0 $((total - 1))); do
        local test_case
        test_case=$(jq -c ".test_cases[$i]" "$TEST_SCENARIOS" 2>/dev/null)
        if [[ $? -ne 0 || -z "$test_case" ]]; then
            continue
        fi

        local expected
        expected=$(echo "$test_case" | jq -r '.expected.container_security_allow' 2>/dev/null)
        if [[ "$expected" == "null" ]]; then
            continue
        fi

        local test_name=$(echo "$test_case" | jq -r '.name')
        local input_data=$(echo "$test_case" | jq -c '.input')

        if ! run_policy_test "$test_name" "" "data.container_security.allow" "$input_data" "$expected"; then
            ((failed++))
        fi
    done

    echo -e "${BLUE}Vulnerability policy: $((total - failed))/$total tests passed${NC}"
    return $failed
}

test_signature_policy() {
    log "Testing signature policy..."

    local failed=0
    local total=0

    # Test cases from JSON
    local test_cases
    test_cases=$(jq -c '.test_cases[] | select(.expected.signature_policy_allow != null)' "$TEST_SCENARIOS" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to parse test scenarios${NC}"
        return 1
    fi

    echo "$test_cases" | while read -r test_case; do
        if [[ -z "$test_case" ]]; then
            continue
        fi
        ((total++))

        local test_name=$(echo "$test_case" | jq -r '.name')
        local input_data=$(echo "$test_case" | jq -c '.input')
        local expected=$(echo "$test_case" | jq -r '.expected.signature_policy_allow')

        if ! run_policy_test "$test_name" "signature_policy.rego" "data.policies.signature_policy.allow" "$input_data" "$expected"; then
            ((failed++))
        fi
    done

    echo -e "${BLUE}Signature policy: $((total - failed))/$total tests passed${NC}"
    return $failed
}

test_base_image_policy() {
    log "Testing base image policy..."

    local failed=0
    local total=0

    # Test cases from JSON
    local test_cases
    test_cases=$(jq -c '.test_cases[] | select(.expected.base_image_policy_allow != null)' "$TEST_SCENARIOS" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to parse test scenarios${NC}"
        return 1
    fi

    echo "$test_cases" | while read -r test_case; do
        if [[ -z "$test_case" ]]; then
            continue
        fi
        ((total++))

        local test_name=$(echo "$test_case" | jq -r '.name')
        local input_data=$(echo "$test_case" | jq -c '.input')
        local expected=$(echo "$test_case" | jq -r '.expected.base_image_policy_allow')

        if ! run_policy_test "$test_name" "base_image_policy.rego" "data.policies.base_image_policy.allow" "$input_data" "$expected"; then
            ((failed++))
        fi
    done

    echo -e "${BLUE}Base image policy: $((total - failed))/$total tests passed${NC}"
    return $failed
}

test_compliance_policy() {
    log "Testing compliance policy..."

    local failed=0
    local total=0

    # Test cases from JSON
    local test_cases
    test_cases=$(jq -c '.test_cases[] | select(.expected.compliance_policy_allow != null)' "$TEST_SCENARIOS" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to parse test scenarios${NC}"
        return 1
    fi

    echo "$test_cases" | while read -r test_case; do
        if [[ -z "$test_case" ]]; then
            continue
        fi
        ((total++))

        local test_name=$(echo "$test_case" | jq -r '.name')
        local input_data=$(echo "$test_case" | jq -c '.input')
        local expected=$(echo "$test_case" | jq -r '.expected.compliance_policy_allow')

        if ! run_policy_test "$test_name" "compliance_policy.rego" "data.policies.compliance_policy.allow" "$input_data" "$expected"; then
            ((failed++))
        fi
    done

    echo -e "${BLUE}Compliance policy: $((total - failed))/$total tests passed${NC}"
    return $failed
}

test_integration() {
    log "Testing policy integration..."

    local failed=0
    local total=0

    # Count total test cases
    total=$(jq '[.test_cases[] | select(.expected.container_security_allow != null)] | length' "$TEST_SCENARIOS" 2>/dev/null)
    if [[ $? -ne 0 || -z "$total" ]]; then
        echo -e "${RED}Failed to parse test scenarios${NC}"
        return 1
    fi

    # Run tests one by one
    for i in $(seq 0 $((total - 1))); do
        local test_case
        test_case=$(jq -c ".test_cases[$i]" "$TEST_SCENARIOS" 2>/dev/null)
        if [[ $? -ne 0 || -z "$test_case" ]]; then
            continue
        fi

        local expected_allow
        expected_allow=$(echo "$test_case" | jq -r '.expected.container_security_allow' 2>/dev/null)
        if [[ "$expected_allow" == "null" ]]; then
            continue
        fi

        local test_name=$(echo "$test_case" | jq -r '.name')
        local input_data=$(echo "$test_case" | jq -c '.input')
        local expected_reason=$(echo "$test_case" | jq -r '.expected.reason // empty')

        if ! run_integration_test "$test_name" "$input_data" "$expected_allow" "$expected_reason"; then
            ((failed++))
        fi
    done

    echo -e "${BLUE}Integration tests: $((total - failed))/$total tests passed${NC}"
    return $failed
}

# Analyze test results
analyze_results() {
    log "Analyzing test results..."

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log "No test results to analyze"
        return 1
    fi

    local total_files=$(find "$OUTPUT_DIR" -name "*_output.json" | wc -l)
    local passed_tests=0
    local failed_tests=0

    # Count results from log file
    if [[ -f "$LOG_FILE" ]]; then
        passed_tests=$(grep -c "✓ PASS:" "$LOG_FILE")
        failed_tests=$(grep -c "✗ FAIL:" "$LOG_FILE")
    fi

    local total_tests=$((passed_tests + failed_tests))

    log "Test Results Summary:"
    log "  Total test files: $total_files"
    log "  Passed tests: $passed_tests"
    log "  Failed tests: $failed_tests"
    log "  Success rate: $((total_tests > 0 ? (passed_tests * 100) / total_tests : 0))%"
}

# Main test execution
main() {
    local failed_tests=0
    local total_tests=0

    setup

    log "Starting OPA Security Policies tests"
    log "Policies directory: $POLICIES_DIR"
    log "Test scenarios: $TEST_SCENARIOS"

    # Run integration tests (individual policies are tested through container_security)
    echo -e "${BLUE}=== Testing Policy Integration ===${NC}"

    test_integration
    ((failed_tests += $?))
    ((total_tests++))

    # Analyze results
    analyze_results

    # Summary
    log "Overall Test Summary: $((total_tests - failed_tests))/$total_tests policy test suites passed"

    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}All policy tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}$failed_tests policy test suite(s) failed${NC}"
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
    "vulnerability")
        setup
        test_vulnerability_policy
        ;;
    "signature")
        setup
        test_signature_policy
        ;;
    "base-image")
        setup
        test_base_image_policy
        ;;
    "compliance")
        setup
        test_compliance_policy
        ;;
    "integration")
        setup
        test_integration
        ;;
    *)
        main
        ;;
esac
