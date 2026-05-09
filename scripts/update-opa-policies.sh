#!/bin/bash

# Script to update OPA policies dynamically
# Usage: ./update-opa-policies.sh [policy_name] [policy_file]

set -e

# Configuration
OPA_URL="${OPA_URL:-http://localhost:8181}"
POLICIES_DIR="${POLICIES_DIR:-./policies}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if OPA is running
check_opa_health() {
    if ! curl -f -s "${OPA_URL}/health" > /dev/null; then
        log_error "OPA is not running or not accessible at ${OPA_URL}"
        return 1
    fi
    log_info "OPA is healthy"
}

# Function to update a single policy
update_policy() {
    local policy_name=$1
    local policy_file=$2

    if [[ ! -f "$policy_file" ]]; then
        log_error "Policy file not found: $policy_file"
        return 1
    fi

    log_info "Updating policy: $policy_name from $policy_file"

    # Read policy content
    local policy_content
    policy_content=$(cat "$policy_file")

    # Prepare JSON payload
    local payload
    payload=$(jq -n \
        --arg rego "$policy_content" \
        '{rego: $rego}'
    )

    # Send to OPA
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${OPA_URL}/v1/policies/${policy_name}"
    )

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        log_info "Policy $policy_name updated successfully"
        return 0
    else
        log_error "Failed to update policy $policy_name (HTTP $http_code): $body"
        return 1
    fi
}

# Function to update all policies
update_all_policies() {
    log_info "Updating all policies from $POLICIES_DIR"

    local failed_policies=()

    # Find all .rego files
    while IFS= read -r -d '' policy_file; do
        local policy_name
        policy_name=$(basename "$policy_file" .rego)

        if ! update_policy "$policy_name" "$policy_file"; then
            failed_policies+=("$policy_name")
        fi
    done < <(find "$POLICIES_DIR" -name "*.rego" -type f -print0)

    if [[ ${#failed_policies[@]} -gt 0 ]]; then
        log_error "Failed to update policies: ${failed_policies[*]}"
        return 1
    fi

    log_info "All policies updated successfully"
}

# Function to update data
update_data() {
    local data_file="${POLICIES_DIR}/data.json"

    if [[ ! -f "$data_file" ]]; then
        log_warn "Data file not found: $data_file"
        return 0
    fi

    log_info "Updating OPA data from $data_file"

    # Send data to OPA
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        -d @"$data_file" \
        "${OPA_URL}/v1/data"
    )

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        log_info "OPA data updated successfully"
        return 0
    else
        log_error "Failed to update OPA data (HTTP $http_code): $body"
        return 1
    fi
}

# Main script logic
main() {
    # Check dependencies
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    # Check OPA health
    if ! check_opa_health; then
        exit 1
    fi

    # Handle arguments
    case $# in
        0)
            # Update all policies and data
            update_data || exit 1
            update_all_policies || exit 1
            ;;
        1)
            # Update specific policy
            local policy_name=$1
            local policy_file="${POLICIES_DIR}/${policy_name}.rego"
            update_policy "$policy_name" "$policy_file" || exit 1
            ;;
        2)
            # Update specific policy from custom file
            local policy_name=$1
            local policy_file=$2
            update_policy "$policy_name" "$policy_file" || exit 1
            ;;
        *)
            log_error "Usage: $0 [policy_name] [policy_file]"
            log_error "Examples:"
            log_error "  $0                           # Update all policies"
            log_error "  $0 vulnerability_policy      # Update specific policy"
            log_error "  $0 my_policy /path/to/file.rego  # Update from custom file"
            exit 1
            ;;
    esac

    log_info "Policy update completed successfully"
}

# Run main function
main "$@"
