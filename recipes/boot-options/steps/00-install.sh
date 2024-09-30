#!/bin/sh
set -eu

CMDLINE_FILE="${RUGPI_BUNDLE_DIR}/roots/boot/cmdline.txt"

echo "Modifying boot cmdline.txt to enable cgroup memory monitoring" >&2
echo "File: $CMDLINE_FILE (before)" >&2
cat "$CMDLINE_FILE" >&2

CMDLINE_CONTENTS=$(cat "$CMDLINE_FILE")

# remove duplicates, use xargs to trim leading and trailing spaces
CMDLINE_CONTENTS=$(echo "$CMDLINE_CONTENTS" | sed 's/cgroup_memory=[a-z0-9A-Z,]*//g' | xargs)
CMDLINE_CONTENTS=$(echo "$CMDLINE_CONTENTS" | sed 's/cgroup_enable=[a-z0-9A-Z,]*//g' | xargs)

# append cgroup options
printf "%s %s" "$CMDLINE_CONTENTS" "cgroup_memory=1 cgroup_enable=memory" > "$CMDLINE_FILE"

echo "File: $CMDLINE_FILE (after)" >&2
cat "$CMDLINE_FILE" >&2
