#!/bin/bash
# Cosign Image Signing Script
# Signs container images using Cosign (keypair or keyless)

set -e

# Configuration
KEYS_DIR="/opt/cosign/keys"
LOG_FILE="/opt/cosign/logs/signing.log"
SCRIPT_DIR="/opt/cosign/scripts"

# Default values
IMAGE=""
KEY_TYPE="keyless"  # keypair or keyless
PRIVATE_KEY=""
KEY_PASSWORD=""
FULCIO_URL="https://fulcio.sigstore.dev"
REKOR_URL="https://rekor.sigstore.dev"
OIDC_ISSUER="https://oauth2.sigstore.dev/auth"
ANNOTATIONS=""
CERT_IDENTITY=""
CERT_OIDC_ISSUER=""
FORCE=false

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    echo "{\"error\": {\"code\": \"SIGNING_FAILED\", \"message\": \"$1\", \"timestamp\": \"$(date -Iseconds)\"}}" >&2
    exit 1
}

# Success response
success_response() {
    local image="$1"
    local signature_digest="$2"
    local cert_identity="$3"
    local cert_oidc_issuer="$4"

    cat << EOF
{
  "success": true,
  "image": "$image",
  "signature_digest": "$signature_digest",
  "cert_identity": "$cert_identity",
  "cert_oidc_issuer": "$cert_oidc_issuer",
  "timestamp": "$(date -Iseconds)",
  "key_type": "$KEY_TYPE"
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
        --key-type=*)
            KEY_TYPE="${1#*=}"
            shift
            ;;
        --private-key=*)
            PRIVATE_KEY="${1#*=}"
            shift
            ;;
        --key-password=*)
            KEY_PASSWORD="${1#*=}"
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
        --oidc-issuer=*)
            OIDC_ISSUER="${1#*=}"
            shift
            ;;
        --annotations=*)
            ANNOTATIONS="${1#*=}"
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
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 --image=<image> [options]"
            echo "Options:"
            echo "  --image=<image>           Container image to sign (required)"
            echo "  --key-type=<type>         Key type: keypair or keyless (default: keyless)"
            echo "  --private-key=<path>      Path to private key file (for keypair)"
            echo "  --key-password=<pwd>      Password for private key (for keypair)"
            echo "  --fulcio-url=<url>        Fulcio URL for keyless (default: https://fulcio.sigstore.dev)"
            echo "  --rekor-url=<url>         Rekor URL for keyless (default: https://rekor.sigstore.dev)"
            echo "  --oidc-issuer=<url>       OIDC issuer URL (default: https://oauth2.sigstore.dev/auth)"
            echo "  --annotations=<json>      Annotations to add to signature"
            echo "  --cert-identity=<id>       Certificate identity for keyless"
            echo "  --cert-oidc-issuer=<url>  Certificate OIDC issuer for keyless"
            echo "  --force                   Force signing even if already signed"
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

# Validate key type
if [[ "$KEY_TYPE" != "keypair" && "$KEY_TYPE" != "keyless" ]]; then
    error_exit "Invalid key type: $KEY_TYPE. Must be 'keypair' or 'keyless'"
fi

# Prepare common arguments
COSIGN_ARGS=()

if [[ "$FORCE" == "true" ]]; then
    COSIGN_ARGS+=(--force)
fi

if [[ -n "$ANNOTATIONS" ]]; then
    COSIGN_ARGS+=(--annotations "$ANNOTATIONS")
fi

# Start signing process
log "Starting Cosign signing for image: $IMAGE"
log "Key type: $KEY_TYPE"

START_TIME=$(date -Iseconds)

if [[ "$KEY_TYPE" == "keypair" ]]; then
    # Keypair signing
    if [[ -z "$PRIVATE_KEY" ]]; then
        error_exit "Private key path is required for keypair signing"
    fi

    if [[ ! -f "$PRIVATE_KEY" ]]; then
        error_exit "Private key file not found: $PRIVATE_KEY"
    fi

    log "Using private key: $PRIVATE_KEY"

    # Build cosign command for keypair
    COSIGN_CMD=(cosign sign "${COSIGN_ARGS[@]}" --key "$PRIVATE_KEY")

    # Add password if provided
    if [[ -n "$KEY_PASSWORD" ]]; then
        COSIGN_CMD=(echo "$KEY_PASSWORD" | "${COSIGN_CMD[@]}")
    fi

    COSIGN_CMD+=("$IMAGE")

elif [[ "$KEY_TYPE" == "keyless" ]]; then
    # Keyless signing
    log "Using keyless signing"
    log "Fulcio URL: $FULCIO_URL"
    log "Rekor URL: $REKOR_URL"
    log "OIDC Issuer: $OIDC_ISSUER"

    # Build cosign command for keyless
    COSIGN_CMD=(cosign sign "${COSIGN_ARGS[@]}")

    if [[ -n "$CERT_IDENTITY" ]]; then
        COSIGN_CMD+=(--certificate-identity "$CERT_IDENTITY")
    fi

    if [[ -n "$CERT_OIDC_ISSUER" ]]; then
        COSIGN_CMD+=(--certificate-oidc-issuer "$CERT_OIDC_ISSUER")
    fi

    COSIGN_CMD+=(--fulcio-url "$FULCIO_URL")
    COSIGN_CMD+=(--rekor-url "$REKOR_URL")
    COSIGN_CMD+=(--oidc-issuer "$OIDC_ISSUER")
    COSIGN_CMD+=("$IMAGE")
fi

# Execute signing command
log "Executing: ${COSIGN_CMD[*]}"

if "${COSIGN_CMD[@]}"; then
    END_TIME=$(date -Iseconds)
    log "Image signing completed successfully"

    # Get signature information
    SIGNATURE_INFO=$(cosign verify "$IMAGE" --certificate-identity-regexp ".*" --certificate-oidc-issuer-regexp ".*" 2>/dev/null || echo "")

    # Extract signature digest if available
    SIGNATURE_DIGEST=""
    CERT_IDENTITY_RESULT=""
    CERT_OIDC_ISSUER_RESULT=""

    if [[ -n "$SIGNATURE_INFO" ]]; then
        # Try to extract some signature information
        SIGNATURE_DIGEST=$(echo "$SIGNATURE_INFO" | grep -o "sha256:[a-f0-9]*" | head -1 || echo "")
    fi

    success_response "$IMAGE" "$SIGNATURE_DIGEST" "$CERT_IDENTITY_RESULT" "$CERT_OIDC_ISSUER_RESULT"

else
    ERROR_CODE=$?
    error_exit "Cosign signing failed with exit code $ERROR_CODE"
fi
