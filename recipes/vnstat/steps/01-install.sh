#!/usr/bin/env bash
set -e

# Persist database
install -D -m 644 "${RECIPE_DIR}/files/vnstat-database.toml" -t /etc/rugix/state

groupmod -g 116 vnstat
usermod -u 116 vnstat

# modify vnstatd service to use --sync which prevents the interface statistics
# being inflated when switching A/B partitions during a firmware update
install -D -m 644 "${RECIPE_DIR}/files/override.conf" -t /etc/systemd/system/vnstat.service.d/
