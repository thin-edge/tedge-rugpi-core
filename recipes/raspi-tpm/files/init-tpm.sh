#!/bin/sh
set -e

# Optional: Token Slot URI
# By default the script will try to find the token slot associated with creating
# a new slot. But this is only needed if the token with the given label does not
# already exist.
TOKEN_URI=
if [ $# -gt 0 ]; then
    TOKEN_URI="$1"
fi

DEVICE_ID="${DEVICE_ID:-}"
export TOKEN_LABEL="${TOKEN_LABEL:-tedge}"
export GNUTLS_PIN="${GNUTLS_PIN:-123456}"
export GNUTLS_SO_PIN="${GNUTLS_SO_PIN:-123456}"
export TPM2_PKCS11_STORE="${TPM2_PKCS11_STORE:-/etc/tedge/tpm2}"
IS_SELF_SIGNED=0

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
    esac
    shift
done

#
# Enable usage with thin-edge.io
#
mkdir -p "$TPM2_PKCS11_STORE"
chown -R tedge:tedge "$TPM2_PKCS11_STORE"
tedge config set device.cryptoki.mode socket

TPM_PKCS11_MODULE=$(find /usr/lib -name libtpm2_pkcs11.so | head -n1)

if ! grep -q '^TEDGE_DEVICE_CRYPTOKI_MODULE_PATH=.\+' /etc/tedge/plugins/tedge-p11-server.conf; then
    cat <<EOT > /etc/tedge/plugins/tedge-p11-server.conf
TEDGE_DEVICE_CRYPTOKI_MODULE_PATH=$TPM_PKCS11_MODULE
TEDGE_DEVICE_CRYPTOKI_PIN=$GNUTLS_PIN
TPM2_PKCS11_STORE="$TPM2_PKCS11_STORE"
EOT
fi

find_slot() {
    p11tool --list-tokens | grep "token=$" | awk '{ print $2 }' 2>/dev/null
}

get_token() {
    p11tool --list-tokens | grep "token=$TOKEN_LABEL" | awk '{ print $2 }' 2>/dev/null
}

get_key() {
    p11tool --login --list-all "$PKCS_URI" 2>/dev/null | grep type=private | awk '{ print $2 }' 2>/dev/null
}

mkdir -p "$TPM2_PKCS11_STORE"

#
# Initialize slot (if it does not already exist)
#
PKCS_URI=$(get_token)
if [ -z "$PKCS_URI" ] ;then
    # Find slot token which is used for initialization
    if [ -z "$TOKEN_URI" ]; then
        echo "Trying to find the empty slot"
        TOKEN_URI=$(find_slot)
    fi

    echo "initializing token: label=$TOKEN_LABEL, token_uri=$TOKEN_URI"
    p11tool --initialize "$TOKEN_URI" --label "$TOKEN_LABEL" || echo "Failed to initialize or it has already been created"
    PKCS_URI=$(get_token)

    echo "Setting the pin and so-pin..."
    p11tool --initialize-pin --initialize-so-pin --set-pin="$GNUTLS_PIN" --set-so-pin "$GNUTLS_SO_PIN" "$PKCS_URI"
fi
echo "Using token URI: $PKCS_URI" >&2

#
# Get/Create private key
#
KEY=$(get_key)
if [ -z "$KEY" ]; then
    echo "Generating private key..."
    p11tool --login --generate-privkey ECDSA --curve=secp256r1  --label "$TOKEN_LABEL" --outfile "$TPM2_PKCS11_STORE/tedge.pub" "$PKCS_URI"
    KEY=$(get_key)
fi

#
# Create Certificate Signing Request (CSR)
#
CSR_TEMPLATE="$TPM2_PKCS11_STORE/cert.template"
if [ ! -f "$CSR_TEMPLATE" ]; then
    if [ -z "${DEVICE_ID:-}" ]; then
        DEVICE_ID=$(tedge-identity 2>/dev/null)
    fi

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
fi

#
# Create CSR (to be signed externally) or create a self-signed certificate
#
if [ "$IS_SELF_SIGNED" = 0 ]; then
    #
    # Create CSR
    #
    CSR_PATH=$(tedge config get device.csr_path)
    certtool --generate-request --template "$CSR_TEMPLATE" --load-privkey "$KEY" --outfile "$CSR_PATH"
    echo "Created csr: $CSR_PATH" >&2
    # tedge cert renew c8y --csr-path "$CSR_PATH"
else
    # Optional: Self sign the Certificate
    echo "Creating self-signed certificate" >&2
    CERT_PATH=$(tedge config get device.cert_path)
    certtool --generate-self-signed --template "$CSR_TEMPLATE" --load-privkey "$KEY" --outfile "$CERT_PATH"
fi

#
# Print info
#
echo
echo You can list the tokens using the tedge user with the following command:
echo
echo   sudo -u tedge TPM2_PKCS11_STORE="$TPM2_PKCS11_STORE" p11tool --list-tokens
echo
echo Reset the TPM store using
echo
echo   rm -rf "$TPM2_PKCS11_STORE"
echo
