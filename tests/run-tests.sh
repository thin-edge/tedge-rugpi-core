#!/usr/bin/env bash
set -e

prepare() {
    if [ ! -f tests/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f tests/id_rsa -q -N ""
    fi

    PUB_KEY="SSH_KEYS_ci=\"$(cat tests/id_rsa.pub)\""
    if grep -q "SSH_KEYS_ci=" .env; then
        echo ".env already contains testing public key"
    else
        echo "$PUB_KEY" >> .env
    fi
}

run() {
    ./run-bakery test
}

prepare
run
