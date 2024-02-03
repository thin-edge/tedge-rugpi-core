#!/bin/bash
set -e

install -D -m 644 "${RECIPE_DIR}/files/mqtt-logger.conf" -t /etc/
install -D -m 755 "${RECIPE_DIR}/files/mqtt-logger" -t /usr/bin/
install -D -m 644 "${RECIPE_DIR}/files/mqtt-logger.service" -t /usr/lib/systemd/system/

if [ "$RECIPE_PARAM_ENABLE_SERVICE" = "true" ]; then
    echo "Enabling mqtt-logger.service" >&2
    systemctl enable mqtt-logger.service
fi
