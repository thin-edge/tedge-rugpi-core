#!/bin/sh
set -e
# Installing systemd-resolved can trigger initramfs-tools to run in the postinst
# apt hooks.
# Prevent initramfs-tools build issues due to not being able to find the
# correct device for the root partition.
# raspberry pi-gen disables the updating of the initramfs during stage-0 and then enables
# it in stage-5 (final stage).
# See https://github.com/RPi-Distro/pi-gen/blob/master/stage0/02-firmware/02-run.sh
# 
if [ -d /etc/initramfs-tools/conf.d ]; then
    echo "MODULES=most" >> /etc/initramfs-tools/conf.d/driver-policy
fi