#!/bin/bash
# Cosign Key Generation Script
# Generates keys for signing container images (keyless or with keys)

set -e

# Configuration
KEYS_DIR="/opt/cosign/keys"
LOG_FILE="/opt/cosign/logs/keygen.log"
SCRIPT_DIR="/opt/cosign/scripts"

# Default values
KEY_TYPE="keypair"  # keypair or keyless
KEY_PASSWORD=""
FULCIO_URL="https://fulcio.sigstore.dev"
REKOR_URL="https://rekor.sigstore.dev"
OIDC_ISSUER="https://oauth2.sigstore.dev/auth"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    echo "{\"error\": {\"code\": \"KEYGEN_FAILED\", \"message\": \"$1\", \"timestamp\": \"$(date -Iseconds)\"}}" >&2
    exit 1
}

# Success response
success_response() {
    local key_type="$1"
    local key_path="$2"
    local public_key_path="$3"

    cat << EOF
{
  "success": true,
  "key_type": "$key_type",
  "key_path": "$key_path",
  "public_key_path": "$public_key_path",
  "timestamp": "$(date -Iseconds)",
  "fulcio_url": "$FULCIO_URL",
  "rekor_url": "$REKOR_URL"
}
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --key-type=*)
            KEY_TYPE="${1#*=}"
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
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --key-type=<type>        Key type: keypair or keyless (default: keypair)"
            echo "  --key-password=<pwd>     Password for keypair (optional)"
            echo "  --fulcio-url=<url>       Fulcio URL for keyless (default: https://fulcio.sigstore.dev)"
            echo "  --rekor-url=<url>        Rekor URL for keyless (default: https://rekor.sigstore.dev)"
            echo "  --oidc-issuer=<url>      OIDC issuer URL (default: https://oauth2.sigstore.dev/auth)"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Create keys directory if it doesn't exist
mkdir -p "$KEYS_DIR"

# Validate key type
if [[ "$KEY_TYPE" != "keypair" && "$KEY_TYPE" != "keyless" ]]; then
    error_exit "Invalid key type: $KEY_TYPE. Must be 'keypair' or 'keyless'"
fi

# Generate timestamp for unique naming
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ "$KEY_TYPE" == "keypair" ]]; then
    # Generate keypair
    log "Generating Cosign keypair..."

    PRIVATE_KEY="$KEYS_DIR/cosign_$TIMESTAMP.key"
    PUBLIC_KEY="$KEYS_DIR/cosign_$TIMESTAMP.pub"

    # Generate keypair with password if provided
    if [[ -n "$KEY_PASSWORD" ]]; then
        echo "$KEY_PASSWORD" | cosign generate-key-pair --output-key-prefix "$KEYS_DIR/cosign_$TIMESTAMP"
    else
        cosign generate-key-pair --output-key-prefix "$KEYS_DIR/cosign_$TIMESTAMP"
    fi

    # Verify keys were created
    if [[ ! -f "$PRIVATE_KEY" || ! -f "$PUBLIC_KEY" ]]; then
        error_exit "Failed to generate keypair"
    fi

    log "Keypair generated successfully"
    log "Private key: $PRIVATE_KEY"
    log "Public key: $PUBLIC_KEY"

    success_response "keypair" "$PRIVATE_KEY" "$PUBLIC_KEY"

elif [[ "$KEY_TYPE" == "keyless" ]]; then
    # Keyless mode - just configure the environment
    log "Configuring keyless signing environment..."
    log "Fulcio URL: $FULCIO_URL"
    log "Rekor URL: $REKOR_URL"
    log "OIDC Issuer: $OIDC_ISSUER"

    # Test connection to services
    if ! curl -s --max-time 10 "$FULCIO_URL/api/v1/rootCert" >/dev/null; then
        log "Warning: Cannot connect to Fulcio service at $FULCIO_URL"
    fi

    if ! curl -s --max-time 10 "$REKOR_URL/api/v1/log/entries" >/dev/null; then
        log "Warning: Cannot connect to Rekor service at $REKOR_URL"
    fi

    log "Keyless signing environment configured"

    success_response "keyless" "" ""

fi
