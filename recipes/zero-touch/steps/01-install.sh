#!/bin/sh
set -eu
install -D -m 644 "${RECIPE_DIR}/files/ztp-agent.toml" -t /etc/rugix/state/

install -D -m 644 "${RECIPE_DIR}/files/flows/deployment-apply/"* -t /etc/tedge/mappers/c8y/flows/deployment-apply/
install -D -m 644 "${RECIPE_DIR}/files/flows/deployment-check/"* -t /etc/tedge/mappers/c8y/flows/deployment-check/
chmod +x /etc/tedge/mappers/c8y/flows/deployment-check/*.sh
chown -R tedge:tedge /etc/tedge/mappers/c8y

