#!/usr/bin/env bash
set -e

# Persist database
install -D -m 644 "${RECIPE_DIR}/files/vnstat-database.toml" -t /etc/rugix/state

groupmod -g 116 vnstat
usermod -u 116 vnstat
