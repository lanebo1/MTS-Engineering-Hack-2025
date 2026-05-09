#!/bin/bash
# Trivy Image Scanner Script
# Scans Docker images for vulnerabilities and exports results in JSON format

set -e

# Configuration
TRIVY_CACHE_DIR="/opt/trivy/cache"
REPORTS_DIR="/opt/trivy/reports"
LOG_FILE="/opt/trivy/scan.log"

# Default values
IMAGE=""
SCAN_TYPES="os,library"
SEVERITY_LEVELS="CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN"
FORMAT="json"
TIMEOUT="300s"
SKIP_DB_UPDATE=false

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    echo "{\"error\": {\"code\": \"SCAN_FAILED\", \"message\": \"$1\", \"timestamp\": \"$(date -Iseconds)\"}}" >&2
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image=*)
            IMAGE="${1#*=}"
            shift
            ;;
        --scan-types=*)
            SCAN_TYPES="${1#*=}"
            shift
            ;;
        --severity=*)
            SEVERITY_LEVELS="${1#*=}"
            shift
            ;;
        --format=*)
            FORMAT="${1#*=}"
            shift
            ;;
        --timeout=*)
            TIMEOUT="${1#*=}"
            shift
            ;;
        --skip-db-update)
            SKIP_DB_UPDATE=true
            shift
            ;;
        --help)
            echo "Usage: $0 --image=<image> [options]"
            echo "Options:"
            echo "  --image=<image>          Docker image to scan (required)"
            echo "  --scan-types=<types>     Scan types: os,library (default: os,library)"
            echo "  --severity=<levels>      Severity levels: CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN (default: all)"
            echo "  --format=<format>        Output format: json,sarif (default: json)"
            echo "  --timeout=<duration>     Scan timeout (default: 300s)"
            echo "  --skip-db-update         Skip database update"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
if [[ -z "$IMAGE" ]]; then
    error_exit "Image parameter is required. Use --image=<image>"
fi

# Create reports directory if it doesn't exist
mkdir -p "$REPORTS_DIR"

# Update Trivy database if not skipped
if [[ "$SKIP_DB_UPDATE" != "true" ]]; then
    log "Updating Trivy vulnerability database..."
    if ! trivy --cache-dir "$TRIVY_CACHE_DIR" image --download-db-only; then
        log "Warning: Failed to update vulnerability database, proceeding with existing database"
    fi
fi

# Generate unique report filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORTS_DIR/scan_${TIMESTAMP}.json"

# Start scan
log "Starting Trivy scan for image: $IMAGE"
log "Scan types: $SCAN_TYPES"
log "Severity levels: $SEVERITY_LEVELS"
log "Output format: $FORMAT"

# Execute Trivy scan
START_TIME=$(date -Iseconds)
if trivy --cache-dir "$TRIVY_CACHE_DIR" \
         --timeout "$TIMEOUT" \
         --format "$FORMAT" \
         --output "$REPORT_FILE" \
         --severity "$SEVERITY_LEVELS" \
         --scanners vuln \
         image "$IMAGE"; then

    SCAN_TIME=$(date -Iseconds)
    log "Scan completed successfully"

    # Process and validate JSON output
    if [[ "$FORMAT" == "json" ]] && [[ -f "$REPORT_FILE" ]]; then
        # Extract vulnerability summary
        if command -v jq >/dev/null 2>&1; then
            VULN_COUNT=$(jq -r '.Results[]?.Vulnerabilities // [] | length' "$REPORT_FILE" 2>/dev/null || echo "0")
            CRITICAL_COUNT=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$REPORT_FILE" 2>/dev/null || echo "0")
            HIGH_COUNT=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$REPORT_FILE" 2>/dev/null || echo "0")
            MEDIUM_COUNT=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "$REPORT_FILE" 2>/dev/null || echo "0")

            log "Scan results: Total vulnerabilities: $VULN_COUNT (Critical: $CRITICAL_COUNT, High: $HIGH_COUNT, Medium: $MEDIUM_COUNT)"
        fi
    fi

    # Output standardized JSON response
    cat << EOF
{
  "success": true,
  "image": "$IMAGE",
  "scan_time": "$SCAN_TIME",
  "start_time": "$START_TIME",
  "vulnerabilities": $(jq -r '.Results[]?.Vulnerabilities // [] | map({
      id: .VulnerabilityID,
      severity: .Severity,
      cvss_score: (.CVSS | .nvd?.V3Score // .nvd?.V2Score // 0),
      package: .PkgName,
      version: .InstalledVersion,
      fixed_version: .FixedVersion,
      description: .Description
    })' "$REPORT_FILE" 2>/dev/null || echo "[]"),
  "summary": {
    "total": ${VULN_COUNT:-0},
    "critical": ${CRITICAL_COUNT:-0},
    "high": ${HIGH_COUNT:-0},
    "medium": ${MEDIUM_COUNT:-0}
  },
  "report_file": "$REPORT_FILE"
}
EOF

else
    ERROR_CODE=$?
    error_exit "Trivy scan failed with exit code $ERROR_CODE"
fi
