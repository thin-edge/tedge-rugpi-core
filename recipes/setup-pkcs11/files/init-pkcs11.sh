#!/bin/sh
set -e

DEVICE_ID="${DEVICE_ID:-}"
C8Y_URL="${C8Y_URL:-}"
DEVICE_ONE_TIME_PASSWORD="${DEVICE_ONE_TIME_PASSWORD:-}"

export GNUTLS_PIN="${GNUTLS_PIN:-123456}"
export GNUTLS_SO_PIN="${GNUTLS_SO_PIN:-123456}"
export TOKEN_LABEL="${TOKEN_LABEL:-tedge}"
export TEDGE_CONFIG_DIR="${TEDGE_CONFIG_DIR:-/etc/tedge}"

# Only used for TPM 2.0
export TPM2_PKCS11_STORE="${TPM2_PKCS11_STORE:-/etc/tedge/hsm}"

PKCS11_MODULE="${PKCS11_MODULE:-}"
PKCS_URI="${PKCS_URI:-}"
IS_SELF_SIGNED=0

ACTION=

HSM_TYPE="${HSM_TYPE:-}"

# For most pkcs11 compatible HSM's, certtool can get the public key automatically, but for Yubikey
# you need to manually export the key using 'ykman piv keys export 9a "<path>"'
PUBLIC_KEY="${PUBLIC_KEY:-$TEDGE_CONFIG_DIR/device-certs/tedge.pub}"

usage() {
    cat <<EOT
$0 [OPTIONS]

ARGUMENTS
  --c8y-url <url>           Cumulocity URL
  --create                  Request a device certificate using the Cumulocity CA
  --renew                   Renew the device certificate using the Cumulocity CA
  --type <string>           Type of HSM (using the PKCS#11 interface) to use. Available values: [softhsm2, yubikey, nitrokey, tpm2]
  --self-signed             Generate a self-signed certificate
  --pin <string>            Pin used to access the HSM
  --so-pin <string>         Special pin
  --device-id <string>      Device ID to use during initialization
  --module <path>           Path to the PKCS#11 module to use
  -p, --one-time-password <string>      one-time-password use to request the certificate from the Cumulocity CA
  --debug                   Enable debugging
  -h, --help                Show this help

EXAMPLES

$0 --type softhsm2 --create --c8y-url example.c8y.io
# Initialize private key using softhsm2, and use the Cumulocity CA to request a certificate

$0 --type softhsm2 --renew
# Renew the device certificate (using the Cumulocity CA) with the private key stored using softhsm2

$0 --type tpm2 --create
# Initialize private key using a tpm 2.0 module, and use the Cumulocity CA to request a certificate

$0 --type tpm2 --renew
# Renew the device certificate (using the Cumulocity CA) with the private key stored using tpm 2.0

EOT
}

#
# Parse arguments
#
while [ $# -gt 0 ]; do
    case "$1" in
        --self-signed)
            IS_SELF_SIGNED=1
            ;;
        --pin)
            GNUTLS_PIN="$2"
            shift
            ;;
        --so-pin)
            GNUTLS_SO_PIN="$2"
            shift
            ;;
        --device-id)
            DEVICE_ID="$2"
            shift
            ;;
        --module)
            PKCS11_MODULE="$2"
            shift
            ;;
        --type)
            HSM_TYPE="$2"
            shift
            ;;
        --c8y-url)
            C8Y_URL="$2"
            shift
            ;;
        --create)
            ACTION="create"
            ;;
        --renew)
            ACTION="renew"
            ;;
        # Cumulocity Enrollment token
        --one-time-password|-p)
            DEVICE_ONE_TIME_PASSWORD="$2"
            shift
            ;;
        --debug)
            set -x
            ;;
        --help|-h)
            usage
            exit 0
            ;;
    esac
    shift
done

if [ -z "${DEVICE_ID:-}" ]; then
    DEVICE_ID=$(tedge config get device.id || tedge-identity 2>/dev/null || hostname)
fi

# Set module defaults
case "$HSM_TYPE" in
    softhsm2)
        if [ -z "$PKCS11_MODULE" ]; then
            PKCS11_MODULE=$(find /usr/lib -name libsofthsm2.so | head -n1)
        fi
        ;;
    tpm2)
        if [ -z "$PKCS11_MODULE" ]; then
            PKCS11_MODULE=$(find /usr/lib -name libtpm2_pkcs11.so | head -n1)
        fi
        ;;
esac

#
# Enable usage with thin-edge.io
#

if [ -n "$C8Y_URL" ]; then
    C8Y_URL=$(echo "$C8Y_URL" | sed 's|https?://||g')
    tedge config set c8y.url "$C8Y_URL"
fi

tedge config set mqtt.bridge.built_in true
tedge config set device.cryptoki.mode socket
if [ -f "$PKCS11_MODULE" ]; then
    if ! grep -q '^TEDGE_DEVICE_CRYPTOKI_MODULE_PATH=.\+' "$TEDGE_CONFIG_DIR/plugins/tedge-p11-server.conf"; then
        cat <<EOT > "$TEDGE_CONFIG_DIR/plugins/tedge-p11-server.conf"
TEDGE_DEVICE_CRYPTOKI_MODULE_PATH=$PKCS11_MODULE
TEDGE_DEVICE_CRYPTOKI_PIN=$GNUTLS_PIN

# TPM specific settings
TPM2_PKCS11_STORE="$TPM2_PKCS11_STORE"
EOT
    fi
elif [ -n "$PKCS11_MODULE" ]; then
    echo "Could not find PKCS11 Module. path=$PKCS11_MODULE" >&2
fi

get_token() {
    p11tool --list-tokens 2>/dev/null | grep "token=$TOKEN_LABEL" | awk '{ print $2 }' | head -n1
}

get_key() {
    p11tool --login --list-all "$PKCS_URI" 2>/dev/null | grep type=private | awk '{ print $2 }' | head -n1
}

init_private_key() {
    case "$1" in
        yubikey|yk|ykman)
            ykman piv keys generate --algorithm ECCP256 9a "$PUBLIC_KEY"
            ;;
        nitrokey)
            p11tool --initialize-pin "$PKCS_URI"
            p11tool --login --generate-privkey ECDSA --curve=secp256r1 --label "$TOKEN_LABEL" --outfile "$PUBLIC_KEY" "$PKCS_URI"
            ;;
        tpm2)
            mkdir -p "$TPM2_PKCS11_STORE"
            chown -R tedge:tedge "$TPM2_PKCS11_STORE"

            p11tool --initialize-pin "$PKCS_URI"
            p11tool --login --generate-privkey ECDSA --curve=secp256r1 --label "$TOKEN_LABEL" --outfile "$PUBLIC_KEY" "$PKCS_URI"
            ;;
        softhsm2|softhsm)
            softhsm2-util --init-token --free --label "$TOKEN_LABEL" --pin "$GNUTLS_PIN" --so-pin "$GNUTLS_SO_PIN"

            # TODO: How to limit changing ownership to the token which was created, as each
            # token is stored in a subfolder, so we should only change the one that was just created
            chown -R tedge:softhsm /var/lib/softhsm/tokens/*
            ;;
        *)
            echo "Warning: Unknown HSM type (name=$1). Trying to initialize using standard p11tool commands" >&2
            p11tool --initialize-pin "$PKCS_URI"
            p11tool --login --generate-privkey ECDSA --curve=secp256r1 --label "$TOKEN_LABEL" --outfile "$PUBLIC_KEY" "$PKCS_URI"
            ;;
    esac
}

get_random_code() {
    awk '
function rand_string(n,         s,i) {
    for ( i=1; i<=n; i++ ) {
        s = s chars[int(1+rand()*numChars)]
    }
    return s
}
BEGIN{
    srand()
    for (i=48; i<=122; i++) {
        char = sprintf("%c", i)
        if ( char ~ /[[:alnum:]]/ ) {
            chars[++numChars] = char
        }
    }

    for (i=1; i<=1; i++) {print rand_string(30)}
}'
}

#
# Get/Init slot
#
if [ -z "$PKCS_URI" ]; then
    PKCS_URI=$(get_token)
fi
if [ -z "$PKCS_URI" ]; then
    init_private_key "$HSM_TYPE"
    PKCS_URI=$(get_token)
fi
echo "Using token URI: $PKCS_URI" >&2


#
# Get/Create key
#
KEY=$(get_key)
if [ -z "$KEY" ]; then
    # NOTE: this make fail for some devices which don't fully comply with the pkcs11 interface
    p11tool --login --generate-privkey ECDSA --curve=secp256r1 --label "tedge" --outfile "$TEDGE_CONFIG_DIR/device-certs/tedge.pub" "$PKCS_URI"
    KEY=$(get_key)
fi


#
# Get/Create CSR template
#
CSR_TEMPLATE="$TEDGE_CONFIG_DIR/device-certs/cert.template"

# If it is self-signed, then Cumulocity requires the ca property
# to be added, otherwise certificate will be rejected by Cumulocity
# when trying to upload it
IS_CA=""
if [ "$IS_SELF_SIGNED" ]; then
    IS_CA="ca"
fi

cat <<EOT > "$CSR_TEMPLATE"
organization = "Thin Edge"
unit = "Test Device"
#state = "QLD"
#country = AU
cn = "$DEVICE_ID"
expiration_days = 365
$IS_CA
EOT

#
# Create CSR (to be signed externally) or create a self-signed certificate
#
# on macOS there is BSD certtool instead of gnu-certtool which have different interfaces
CERT_TOOL="certtool"
if command -V gnutls-certtool >/dev/null 2>&1; then
    CERT_TOOL="gnutls-certtool"
fi

GSED="sed"
if command -V gsed >/dev/null 2>&1; then
    GSED="gsed"
fi

if [ ! -f "$PUBLIC_KEY" ]; then
    case "$HSM_TYPE" in
        yubikey|yk|ykman)
            ykman piv keys export 9a "$PUBLIC_KEY"
            ;;
        nitrokey)
            ;;
        tpm2)
            ;;
        softhsm2|softhsm)
            ;;
        *)
            echo "Warning: Unknown HSM type (name=$HSM_TYPE). You need to init this on your own" >&2
            ;;
    esac
fi

if [ "$IS_SELF_SIGNED" = 0 ]; then
    #
    # Create CSR
    #
    CSR_PATH=$(tedge config get device.csr_path)
    [ -f "$CSR_PATH" ] && chmod 644 "$CSR_PATH"
    
    # Remove --no-text once https://github.com/thin-edge/thin-edge.io/pull/3556 is merged
    "$CERT_TOOL" \
        --generate-request \
        --template "$CSR_TEMPLATE" \
        --load-privkey "$KEY" \
        --load-pubkey "$PUBLIC_KEY" \
        --no-text \
        --outfile "$CSR_PATH"

    # Remove once https://github.com/thin-edge/thin-edge.io/pull/3556 is merged
    echo "Created csr: $CSR_PATH" >&2
    "$GSED" -i 's/NEW CERTIFICATE REQUEST/CERTIFICATE REQUEST/g' "$CSR_PATH"
else
    # Optional: Self sign the Certificate
    echo "Creating self-signed certificate" >&2
    CERT_PATH=$(tedge config get device.cert_path)
    [ -f "$CERT_PATH" ] && chmod 644 "$CERT_PATH"

    # Remove --no-text once https://github.com/thin-edge/thin-edge.io/pull/3556 is merged
    "$CERT_TOOL" \
        --generate-self-signed \
        --template "$CSR_TEMPLATE" \
        --load-privkey "$KEY" \
        --load-pubkey "$PUBLIC_KEY" \
        --no-text \
        --outfile "$CERT_PATH"
    # Remove once https://github.com/thin-edge/thin-edge.io/pull/3556 is merged
    "$GSED" -i 's/NEW CERTIFICATE REQUEST/CERTIFICATE REQUEST/g' "$CSR_PATH"
    chmod 444 "$CERT_PATH" ||:
fi

case "$ACTION" in
    renew)
        tedge cert renew c8y --csr-path "$CSR_PATH"
        tedge reconnect c8y
        echo "Renewed certificate successfully" >&2
        ;;
    create)
        if [ -z "$DEVICE_ONE_TIME_PASSWORD" ]; then
            # Generate a code
            DEVICE_ONE_TIME_PASSWORD=$(get_random_code)
        fi

        if [ -n "$C8Y_URL" ]; then
            echo "Register in Cumulocity using:" >&2
            echo "" >&2
            echo "  https://$C8Y_URL/apps/devicemanagement/index.html#/deviceregistration?externalId=$DEVICE_ID&one-time-password=$DEVICE_ONE_TIME_PASSWORD" >&2
            echo "" >&2
        fi

        tedge cert download c8y --device-id "$DEVICE_ID" --csr-path "$CSR_PATH" --token "$DEVICE_ONE_TIME_PASSWORD" --retry-every 5s
        tedge reconnect c8y
        echo "Downloaded certificate successfully" >&2
        ;;
    *)
        # Don't do any other action, just show information to the user
        echo "" >&2
        echo "Download Cumulocity Certificate" >&2
        echo >&2
        echo "  tedge cert download c8y --device-id '$DEVICE_ID' --csr-path '$CSR_PATH'" >&2
        ;;
esac
