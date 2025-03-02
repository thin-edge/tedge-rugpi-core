# Load system recipes (generated via `just gen`)
import 'systems.just'

# System image. Default to amd64 if the arch does not match
DEFAULT_SYSTEM := if arch() == "aarch64" {
    "tedge-debian-12-efi-arm64"
} else if arch() == "x86_64"  {
    "tedge-debian-12-efi-amd64"
} else {
    "tedge-debian-12-efi-amd64"
}

SYSTEM := env("SYSTEM", DEFAULT_SYSTEM)

# Default version (info only)
export VERSION := env_var_or_default("VERSION", `date +'%Y%m%d.%H%M'`)

# Use ipv6 network on the host so it does not conflict with the docker in docker inside the VM
# See https://github.com/silitics/rugix/issues/49
DOCKER_NETWORK := "rugix-net"
DOCKER_FLAGS := "--network=" + DOCKER_NETWORK

# Generate a version name (that can be used in follow up commands)
generate_version:
    @echo "{{VERSION}}"

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

    docker network inspect {{DOCKER_NETWORK}} >/dev/null 2>&1 || docker network create --ipv6 -o com.docker.network.enable_ipv4=false {{DOCKER_NETWORK}}

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
build-image OUTPUT="system.img":
    ./run-bakery bake image {{SYSTEM}} build/{{SYSTEM}}/{{OUTPUT}}

# Build bundle (uncompressed)
build-bundle-uncompressed OUTPUT="system.rugixb":
    ./run-bakery bake bundle --without-compression {{SYSTEM}} build/{{SYSTEM}}/{{OUTPUT}}

# Build build (compressed)
build-bundle OUTPUT="system.rugixb":
    ./run-bakery bake bundle {{SYSTEM}} build/{{SYSTEM}}/{{OUTPUT}}

# Run integration tests
test:
    ./tests/run-tests.sh

# Start vm
start-vm: prepare
    DOCKER_FLAGS="{{DOCKER_FLAGS}}" ./run-bakery run {{SYSTEM}}

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
