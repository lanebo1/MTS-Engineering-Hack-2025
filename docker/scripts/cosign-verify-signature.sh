#!/bin/bash
# Cosign Signature Verification Script
# Verifies container image signatures using Cosign

set -e

# Configuration
LOG_FILE="/opt/cosign/logs/verification.log"
SCRIPT_DIR="/opt/cosign/scripts"

# Default values
IMAGE=""
PUBLIC_KEY=""
CERT_IDENTITY=""
CERT_OIDC_ISSUER=""
FULCIO_URL="https://fulcio.sigstore.dev"
REKOR_URL="https://rekor.sigstore.dev"
ALLOW_UNSIGNED=false
CHECK_CLAIMS=false

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    echo "{\"error\": {\"code\": \"VERIFICATION_FAILED\", \"message\": \"$1\", \"timestamp\": \"$(date -Iseconds)\"}}" >&2
    exit 1
}

# Success response
success_response() {
    local image="$1"
    local is_signed="$2"
    local signature_count="$3"
    local cert_info="$4"

    cat << EOF
{
  "success": true,
  "image": "$image",
  "is_signed": $is_signed,
  "signature_count": $signature_count,
  "certificate_info": $cert_info,
  "timestamp": "$(date -Iseconds)",
  "verification_passed": true
}
EOF
}

# Failure response for verification
verification_failed_response() {
    local image="$1"
    local reason="$2"

    cat << EOF
{
  "success": true,
  "image": "$image",
  "is_signed": false,
  "signature_count": 0,
  "certificate_info": null,
  "timestamp": "$(date -Iseconds)",
  "verification_passed": false,
  "failure_reason": "$reason"
}
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image=*)
            IMAGE="${1#*=}"
            shift
            ;;
        --public-key=*)
            PUBLIC_KEY="${1#*=}"
            shift
            ;;
        --cert-identity=*)
            CERT_IDENTITY="${1#*=}"
            shift
            ;;
        --cert-oidc-issuer=*)
            CERT_OIDC_ISSUER="${1#*=}"
            shift
            ;;
        --fulcio-url=*)
            FULCIO_URL="${1#*=}"
            shift
            ;;
        --rekor-url=*)
            REKOR_URL="${1#*=}"
            shift
            ;;
        --allow-unsigned)
            ALLOW_UNSIGNED=true
            shift
            ;;
        --check-claims)
            CHECK_CLAIMS=true
            shift
            ;;
        --help)
            echo "Usage: $0 --image=<image> [options]"
            echo "Options:"
            echo "  --image=<image>           Container image to verify (required)"
            echo "  --public-key=<path>       Path to public key file (for keypair verification)"
            echo "  --cert-identity=<id>       Certificate identity for keyless verification"
            echo "  --cert-oidc-issuer=<url>  Certificate OIDC issuer for keyless verification"
            echo "  --fulcio-url=<url>        Fulcio URL (default: https://fulcio.sigstore.dev)"
            echo "  --rekor-url=<url>         Rekor URL (default: https://rekor.sigstore.dev)"
            echo "  --allow-unsigned          Allow unsigned images (don't fail if no signature)"
            echo "  --check-claims            Check signature claims"
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

# Prepare cosign verify command
COSIGN_CMD=(cosign verify)

# Add verification options
if [[ -n "$PUBLIC_KEY" ]]; then
    if [[ ! -f "$PUBLIC_KEY" ]]; then
        error_exit "Public key file not found: $PUBLIC_KEY"
    fi
    COSIGN_CMD+=(--key "$PUBLIC_KEY")
    VERIFICATION_TYPE="keypair"
elif [[ -n "$CERT_IDENTITY" || -n "$CERT_OIDC_ISSUER" ]]; then
    if [[ -n "$CERT_IDENTITY" ]]; then
        COSIGN_CMD+=(--certificate-identity "$CERT_IDENTITY")
    fi
    if [[ -n "$CERT_OIDC_ISSUER" ]]; then
        COSIGN_CMD+=(--certificate-oidc-issuer "$CERT_OIDC_ISSUER")
    fi
    COSIGN_CMD+=(--certificate-github-workflow-trigger)
    VERIFICATION_TYPE="keyless"
else
    # Default keyless verification with broad permissions
    COSIGN_CMD+=(--certificate-identity-regexp ".*")
    COSIGN_CMD+=(--certificate-oidc-issuer-regexp ".*")
    VERIFICATION_TYPE="keyless-broad"
fi

if [[ "$CHECK_CLAIMS" == "true" ]]; then
    COSIGN_CMD+=(--check-claims)
fi

COSIGN_CMD+=("$IMAGE")

# Start verification process
log "Starting Cosign verification for image: $IMAGE"
log "Verification type: $VERIFICATION_TYPE"

START_TIME=$(date -Iseconds)

# Execute verification command and capture output
if VERIFICATION_OUTPUT=$("${COSIGN_CMD[@]}" 2>&1); then
    END_TIME=$(date -Iseconds)
    log "Signature verification successful"

    # Parse verification output to extract information
    SIGNATURE_COUNT=$(echo "$VERIFICATION_OUTPUT" | grep -c "Verification for" || echo "1")

    # Extract certificate information
    CERT_INFO=$(echo "$VERIFICATION_OUTPUT" | jq -R -s '
        split("\n") |
        map(select(length > 0 and contains("Certificate"))) |
        if length > 0 then
            {certificates: .}
        else
            null
        end
    ' 2>/dev/null || echo "null")

    success_response "$IMAGE" true "$SIGNATURE_COUNT" "$CERT_INFO"

else
    ERROR_CODE=$?
    log "Cosign verification failed with exit code $ERROR_CODE"

    # Check if image is unsigned
    if echo "$VERIFICATION_OUTPUT" | grep -qi "no signatures found\|none of the signatures were verified"; then
        if [[ "$ALLOW_UNSIGNED" == "true" ]]; then
            log "Image is unsigned but allowing as requested"
            verification_failed_response "$IMAGE" "unsigned_image_allowed"
            exit 0
        else
            log "Image verification failed: unsigned image"
            verification_failed_response "$IMAGE" "unsigned_image_not_allowed"
            exit 1
        fi
    else
        error_exit "Signature verification failed: $(echo "$VERIFICATION_OUTPUT" | head -3 | tr '\n' '; ')"
    fi
fi
