#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/ztp-agent.toml" -t /etc/rugix/state/

# Unblock bluetooth as it is needed for discovery
if [ "$RECIPE_PARAM_DISABLE_RFKILL" = "true" ] && [ -d /var/lib/systemd/rfkill ]; then
    echo "Enabling bluetooth on devices by default" >&2
    for filename in /var/lib/systemd/rfkill/*:bluetooth; do
        echo 0 > "$filename"
    done
fi
