#!/bin/sh
set -eu

# Disable rfkill persistence
systemctl mask systemd-rfkill.service
systemctl mask systemd-rfkill.socket

# Clean any baked-in state
rm -rf /var/lib/systemd/rfkill/*
