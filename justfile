# Load system recipes (generated via `just gen`)
import 'systems.just'

# System image. Default to amd64 if the arch does not match
DEFAULT_SYSTEM := if arch() == "aarch64" {
    "debian-bookworm-tedge-efi-arm64"
} else if arch() == "x86_64"  {
    "debian-bookworm-tedge-efi-amd64"
} else {
    "debian-bookworm-tedge-efi-amd64"
}

SYSTEM := env("SYSTEM", DEFAULT_SYSTEM)

prepare:
    #!/usr/bin/env bash
    if [ ! -f tests/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -f tests/id_rsa -q -N ""
    fi

    PUB_KEY="SSH_KEYS_ci=\"$(cat tests/id_rsa.pub)\""
    if grep -q "SSH_KEYS_ci=" .env; then
        echo ".env already contains testing public key"
    else
        echo "$PUB_KEY" >> .env
    fi

# list available systems that can be built
list-systems:
    ./run-bakery list systems

    @echo
    @echo just SYSTEM=example build-image
    @echo

# Install cross-platform tools
build-setup:
    docker run --privileged --rm tonistiigi/binfmt --install all

# Build an image
build-image:
    ./run-bakery bake image {{SYSTEM}}

# Build bundle (uncompressed)
build-bundle-uncompressed:
    ./run-bakery bake bundle --without-compression {{SYSTEM}}

# Build build (compressed)
build-bundle:
    ./run-bakery bake bundle {{SYSTEM}}

# Run integration tests
test:
    ./tests/run-tests.sh

# Start vm
start-vm: prepare
    ./run-bakery run {{SYSTEM}}

# Connect to vm
connect-vm:
    [ -f ./tests/id_rsa ] && ssh-add ./tests/id_rsa
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@127.0.0.1

# Generate just file for system images (for improved tab completion)
generate:
    #!/bin/sh -e
    echo "# Auto generated: DO NOT EDIT" > systems.just
    
    for name in $(grep '\[systems..*]' rugix-bakery.toml | tr -d '[]' | cut -d. -f2-); do
        echo "" >> systems.just
        echo "# system: $name" >> systems.just
        echo "$name type='image':" >> systems.just
        echo "    just SYSTEM=$name build-{{{{type}}" >> systems.just
    done
