#!/bin/sh
set -e

export GNUTLS_PIN="${GNUTLS_PIN:-123456}"
export GNUTLS_SO_PIN="${GNUTLS_SO_PIN:-123456}"
export TOKEN_LABEL="${TOKEN_LABEL:-tedge}"
PKCS_URI=

get_token() {
    p11tool --list-tokens | grep "token=$TOKEN_LABEL" | awk '{ print $2 }' | head -n1
}

get_key() {
    p11tool --login --list-all "$PKCS_URI" | grep type=private | awk '{ print $2 }'
}

#
# Get/Init slot
#
PKCS_URI=$(get_token)
if [ -z "$(get_token)" ]; then
    echo "Initializing softhsm2 token" >&2
    softhsm2-util --init-token --free --label "$TOKEN_LABEL" --pin "$GNUTLS_PIN" --so-pin "$GNUTLS_SO_PIN"
    PKCS_URI=$(get_token)
fi
echo "Using token URI: $PKCS_URI" >&2


#
# Get/Create key
#
KEY=$(get_key)
if [ -z "$KEY" ]; then
    mkdir -p /etc/tedge/hsm
    p11tool --login --generate-privkey ECDSA --curve=secp256r1  --label "tedge" --outfile /etc/tedge/hsm/tedge.pub "$PKCS_URI"
    KEY=$(get_key)
fi


#
# Get/Create CSR template
#
CSR_TEMPLATE=/etc/tedge/hsm/cert.template
if [ ! -f "$CSR_TEMPLATE" ]; then
    DEVICE_ID=$(tedge-identity 2>/dev/null)
    cat <<EOT > "$CSR_TEMPLATE"
organization = "Thin Edge"
unit = "Test Device"
#state = "QLD"
#country = AU
cn = "$DEVICE_ID"
EOT
fi

#
# Create CSR
#
CSR_PATH=$(tedge config get device.csr_path)
certtool --generate-request --template "$CSR_TEMPLATE" --load-privkey "$KEY" --outfile "$CSR_PATH"
echo "Created csr: $CSR_PATH" >&2
