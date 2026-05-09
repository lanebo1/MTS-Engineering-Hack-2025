#!/bin/bash
# Generate consolidated security scan report from multiple scan results
# Usage: ./generate-consolidated-report.sh <reports_dir> <output_file>

set -e

REPORTS_DIR="$1"
OUTPUT_FILE="$2"

if [ -z "$REPORTS_DIR" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <reports_dir> <output_file>"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Initialize consolidated report
cat > "$OUTPUT_FILE" << 'EOF'
{
  "report_type": "consolidated_security_scan",
  "timestamp": "'$(date -Iseconds)'",
  "pipeline_id": "'${CI_PIPELINE_ID:-unknown}'",
  "commit_sha": "'${CI_COMMIT_SHA:-unknown}'",
  "branch": "'${CI_COMMIT_REF_NAME:-unknown}'",
  "scans": [],
  "summary": {
    "total_scans": 0,
    "total_vulnerabilities": 0,
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "unknown": 0,
    "scanned_images": []
  }
}
EOF

# Find all scan result files
SCAN_FILES=$(find "$REPORTS_DIR" -name "scan_*.json" -type f)

if [ -z "$SCAN_FILES" ]; then
    echo "Warning: No scan result files found in $REPORTS_DIR"
    exit 0
fi

echo "Processing $(echo "$SCAN_FILES" | wc -l) scan result files..."

# Process each scan file
SCAN_COUNT=0
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0
TOTAL_UNKNOWN=0
TOTAL_VULNS=0
SCANNED_IMAGES="[]"

for scan_file in $SCAN_FILES; do
    if [ ! -f "$scan_file" ] || ! jq empty "$scan_file" 2>/dev/null; then
        echo "Warning: Skipping invalid scan file: $scan_file"
        continue
    fi

    echo "Processing: $(basename "$scan_file")"

    # Extract data from scan result
    IMAGE=$(jq -r '.image // "unknown"' "$scan_file")
    SCAN_SUCCESS=$(jq -r '.success // false' "$scan_file")
    SCAN_TIME=$(jq -r '.scan_time // "unknown"' "$scan_file")

    if [ "$SCAN_SUCCESS" != "true" ]; then
        echo "Warning: Scan failed for $IMAGE"
        continue
    fi

    # Extract vulnerability counts
    CRITICAL_COUNT=$(jq -r '.summary.critical // 0' "$scan_file")
    HIGH_COUNT=$(jq -r '.summary.high // 0' "$scan_file")
    MEDIUM_COUNT=$(jq -r '.summary.medium // 0' "$scan_file")
    LOW_COUNT=$(jq -r '.summary.low // 0' "$scan_file")
    UNKNOWN_COUNT=$(jq -r '.summary.unknown // 0' "$scan_file")
    TOTAL_COUNT=$(jq -r '.summary.total // 0' "$scan_file")

    # Update totals
    SCAN_COUNT=$((SCAN_COUNT + 1))
    TOTAL_CRITICAL=$((TOTAL_CRITICAL + CRITICAL_COUNT))
    TOTAL_HIGH=$((TOTAL_HIGH + HIGH_COUNT))
    TOTAL_MEDIUM=$((TOTAL_MEDIUM + MEDIUM_COUNT))
    TOTAL_LOW=$((TOTAL_LOW + LOW_COUNT))
    TOTAL_UNKNOWN=$((TOTAL_UNKNOWN + UNKNOWN_COUNT))
    TOTAL_VULNS=$((TOTAL_VULNS + TOTAL_COUNT))

    # Add to scanned images array
    SCANNED_IMAGES=$(echo "$SCANNED_IMAGES" | jq --arg image "$IMAGE" '. + [$image]')

    # Create scan entry
    SCAN_ENTRY=$(cat << EOF
{
  "image": "$IMAGE",
  "scan_time": "$SCAN_TIME",
  "success": $SCAN_SUCCESS,
  "vulnerabilities": {
    "total": $TOTAL_COUNT,
    "critical": $CRITICAL_COUNT,
    "high": $HIGH_COUNT,
    "medium": $MEDIUM_COUNT,
    "low": $LOW_COUNT,
    "unknown": $UNKNOWN_COUNT
  },
  "report_file": "$(basename "$scan_file")"
}
EOF
)

    # Add scan entry to consolidated report
    jq --argjson scan "$SCAN_ENTRY" '.scans += [$scan]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
done

# Update summary in consolidated report
jq \
    --arg total_scans "$SCAN_COUNT" \
    --arg total_vulns "$TOTAL_VULNS" \
    --arg critical "$TOTAL_CRITICAL" \
    --arg high "$TOTAL_HIGH" \
    --arg medium "$TOTAL_MEDIUM" \
    --arg low "$TOTAL_LOW" \
    --arg unknown "$TOTAL_UNKNOWN" \
    --argjson images "$SCANNED_IMAGES" \
    '.summary.total_scans = ($total_scans | tonumber) |
     .summary.total_vulnerabilities = ($total_vulns | tonumber) |
     .summary.critical = ($critical | tonumber) |
     .summary.high = ($high | tonumber) |
     .summary.medium = ($medium | tonumber) |
     .summary.low = ($low | tonumber) |
     .summary.unknown = ($unknown | tonumber) |
     .summary.scanned_images = $images' \
    "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

echo "Consolidated report generated: $OUTPUT_FILE"
echo "Summary: $SCAN_COUNT scans processed, $TOTAL_VULNS total vulnerabilities found"
