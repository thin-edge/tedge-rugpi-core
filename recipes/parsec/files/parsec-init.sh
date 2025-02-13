#!/bin/sh
set -e
USER_PIN="${USER_PIN:-123456}"
SO_PIN="${SO_PIN:-123456}"

init_pkcs11_softhsm() {

    if [ -f /etc/parsec/config.pkcs11-provider.toml ]; then
        echo "parsec pkcs11-provider has already been initialized" >&2
        return 0
    fi

    softhsm2-util --init-token --slot 0 --label "tedge" --pin "$USER_PIN" --so-pin "$SO_PIN"
    chown -R parsec:softhsm /var/lib/softhsm/tokens/*

    PKCS11_MODULE="/usr/lib/softhsm/libsofthsm2.so"
    SLOT_NUMBER=$(softhsm2-util --show-slots | head -n2 | tail -n1 | cut -d " " -f 2)

    # sed -i "s/^# library_path.*$/library_path = \"$PKCS11_MODULE\"/g" /etc/parsec/config.toml
    # sed -i "s/^# slot_number.*$/slot_number = $SLOT_NUMBER/g" /etc/parsec/config.toml
    # sed -i "s/^# user_pin.*$/user_pin = \"$USER_PIN\"/g" /etc/parsec/config.toml

    cat <<EOT >> /etc/parsec/config.pkcs11-provider.toml
[[provider]]
name = "pkcs11-provider"
provider_type = "Pkcs11"
key_info_manager = "sqlite-manager"

library_path = "$PKCS11_MODULE"
slot_number = $SLOT_NUMBER
user_pin = "$PIN"
EOT
}

init_tpm() {
    # Allow user access to /dev/tpmrm0
    usermod -a -g tss parsec ||:
}

build_parsec_config() {
    # Build the config.toml
    if ls /etc/parsec/config.*.toml >/dev/null 2>&1; then
        cat /etc/parsec/config.*.toml > /etc/parsec/config.toml
    fi
}

main() {
    init_pkcs11_softhsm
    build_parsec_config
}

main "$@"
