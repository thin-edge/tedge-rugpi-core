#!/bin/bash
set -e

has_command() { command -V "$1" >/dev/null 2>&1; }

if has_command apt; then
    # Debian based
    curl -1sLf 'https://dl.cloudsmith.io/public/thinedge/tedge-dev/setup.deb.sh' | bash
elif has_command apk; then
    # Alpine linux
    curl -1sLf 'https://dl.cloudsmith.io/public/thinedge/tedge-dev/setup.alpine.sh' | bash
elif has_command dnf || has_command yum; then
    # Fedora / RHEL etc.
    # Note: These are probably not supported anyway, but just adding them for completeness
    curl -1sLf 'https://dl.cloudsmith.io/public/thinedge/tedge-dev/setup.rpm.sh' | bash
fi
