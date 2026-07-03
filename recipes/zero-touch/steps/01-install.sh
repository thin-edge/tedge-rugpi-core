#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/ztp-agent.toml" -t /etc/rugix/state/

install -D -m 644 "${RECIPE_DIR}/files/flows/deployment-request/"* -t /etc/tedge/mappers/c8y/flows/deployment-request/
install -D -m 644 "${RECIPE_DIR}/files/flows/deployment-target/"* -t /etc/tedge/mappers/c8y/flows/deployment-target/
install -D -m 644 "${RECIPE_DIR}/files/flows/deployment-track/"* -t /etc/tedge/mappers/c8y/flows/deployment-track/
chmod +x /etc/tedge/mappers/c8y/flows/deployment-request/*.sh
chown -R tedge:tedge /etc/tedge/mappers/c8y

