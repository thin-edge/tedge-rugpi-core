#!/bin/bash -e

# set sensible storage limits
install -D -m 644 "${RECIPE_DIR}/files/00-storage-limits.conf" -t /etc/systemd/journald.conf.d/
