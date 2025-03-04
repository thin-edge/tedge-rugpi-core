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

export TOKEN_LABEL="${TOKEN_LABEL:-tedge}"
export GNUTLS_PIN="${GNUTLS_PIN:-123456}"
export GNUTLS_SO_PIN="${GNUTLS_SO_PIN:-123456}"
export TPM2_PKCS11_STORE="${TPM2_PKCS11_STORE:-/etc/tedge/tpm2}"

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
DEVICE_ID=$(tedge-identity 2>/dev/null || hostname)
echo "Creating CSR...CN=$DEVICE_ID"
cat <<EOT > "$TPM2_PKCS11_STORE/cert.template"
organization = "Thin Edge"
unit = "Test Device"
#state = "QLD"
#country = AU
cn = "$DEVICE_ID"
expiration_days = 365
EOT

CSR_PATH=$(tedge config get device.csr_path)

certtool --generate-request --template "$TPM2_PKCS11_STORE/cert.template" --load-privkey "$KEY" --outfile "$CSR_PATH"
echo "Created CSR: $CSR_PATH"
cat "$CSR_PATH"

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
