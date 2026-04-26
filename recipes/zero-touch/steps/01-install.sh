#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/ztp-agent.toml" -t /etc/rugix/state/
