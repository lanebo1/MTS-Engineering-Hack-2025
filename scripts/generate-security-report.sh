#!/bin/bash
# Generate human-readable security report from scan results
# Usage: ./generate-security-report.sh <consolidated_report.json> <output_file.md>

set -e

REPORT_FILE="$1"
OUTPUT_FILE="$2"

if [ -z "$REPORT_FILE" ] || [ -z "$OUTPUT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
    echo "Usage: $0 <consolidated_report.json> <output_file.md>"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Extract data from report
TIMESTAMP=$(jq -r '.timestamp' "$REPORT_FILE")
PIPELINE_ID=$(jq -r '.pipeline_id' "$REPORT_FILE")
COMMIT_SHA=$(jq -r '.commit_sha' "$REPORT_FILE")
BRANCH=$(jq -r '.branch' "$REPORT_FILE")

TOTAL_SCANS=$(jq -r '.summary.total_scans' "$REPORT_FILE")
TOTAL_VULNS=$(jq -r '.summary.total_vulnerabilities' "$REPORT_FILE")
CRITICAL=$(jq -r '.summary.critical' "$REPORT_FILE")
HIGH=$(jq -r '.summary.high' "$REPORT_FILE")
MEDIUM=$(jq -r '.summary.medium' "$REPORT_FILE")
LOW=$(jq -r '.summary.low' "$REPORT_FILE")
UNKNOWN=$(jq -r '.summary.unknown' "$REPORT_FILE")

# Generate Markdown report
cat > "$OUTPUT_FILE" << EOF
# 🔒 Security Scan Report

**Generated:** $TIMESTAMP
**Pipeline:** $PIPELINE_ID
**Branch:** $BRANCH
**Commit:** \`$COMMIT_SHA\`

## 📊 Executive Summary

| Metric | Value |
|--------|-------|
| Total Scans | $TOTAL_SCANS |
| Total Vulnerabilities | $TOTAL_VULNS |
| Critical | 🔴 $CRITICAL |
| High | 🟠 $HIGH |
| Medium | 🟡 $MEDIUM |
| Low | 🔵 $LOW |
| Unknown | ⚪ $UNKNOWN |

EOF

# Risk assessment
if [ "$CRITICAL" -gt 0 ]; then
    RISK_LEVEL="🚫 CRITICAL"
    RISK_DESC="Immediate action required. Critical vulnerabilities detected."
elif [ "$HIGH" -gt 5 ]; then
    RISK_LEVEL="⚠️ HIGH"
    RISK_DESC="Multiple high-severity vulnerabilities require attention."
elif [ "$HIGH" -gt 0 ] || [ "$MEDIUM" -gt 10 ]; then
    RISK_LEVEL="⚡ MEDIUM"
    RISK_DESC="Some vulnerabilities present. Review recommended."
else
    RISK_LEVEL="✅ LOW"
    RISK_DESC="Acceptable vulnerability levels."
fi

cat >> "$OUTPUT_FILE" << EOF

## 🎯 Risk Assessment

**Overall Risk Level:** $RISK_LEVEL

$RISK_DESC

EOF

# Individual scan results
cat >> "$OUTPUT_FILE" << EOF

## 🔍 Scan Results Details

| Image | Total Vulns | Critical | High | Medium | Status |
|-------|-------------|----------|------|--------|--------|
EOF

# Add table rows for each scan
jq -r '.scans[] | "| \(.image) | \(.vulnerabilities.total) | \(.vulnerabilities.critical) | \(.vulnerabilities.high) | \(.vulnerabilities.medium) | ✅ Success |"' "$REPORT_FILE" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << EOF

## 📋 Recommendations

EOF

# Generate recommendations based on findings
if [ "$CRITICAL" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF
### 🚫 Critical Issues
- **IMMEDIATE ACTION REQUIRED**: $CRITICAL critical vulnerabilities found
- Stop deployment until critical issues are resolved
- Review and apply security patches immediately
- Consider emergency security updates

EOF
fi

if [ "$HIGH" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF
### ⚠️ High Priority
- $HIGH high-severity vulnerabilities need attention
- Plan security updates in next sprint
- Consider impact on production systems

EOF
fi

if [ "$MEDIUM" -gt 0 ] || [ "$LOW" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF
### 📝 General Improvements
- Address $MEDIUM medium and $LOW low-severity issues
- Keep dependencies updated
- Regular security scans recommended

EOF
fi

# Best practices section
cat >> "$OUTPUT_FILE" << EOF
## 🛡️ Security Best Practices

- [ ] Use minimal base images (distroless, alpine)
- [ ] Regularly update dependencies
- [ ] Implement dependency scanning in CI/CD
- [ ] Use signed images when possible
- [ ] Monitor for new vulnerabilities
- [ ] Implement proper secrets management

## 📈 Metrics

\`\`\`
# Prometheus metrics for monitoring
critical_vulnerabilities_total{branch="$BRANCH"} $CRITICAL
high_vulnerabilities_total{branch="$BRANCH"} $HIGH
security_scans_total{result="success",branch="$BRANCH"} $TOTAL_SCANS
\`\`\`

---

*Report generated automatically by Container Security Scanner*
EOF

echo "Security report generated: $OUTPUT_FILE"
