#!/bin/sh
set -eu

CMDLINE_FILE="${RUGIX_LAYER_DIR}/roots/boot/cmdline.txt"
mkdir -p "${RUGIX_LAYER_DIR}/roots/boot"

echo "Modifying boot cmdline.txt to enable cgroup memory monitoring" >&2

CMDLINE_CONTENTS=""
if [ -f "$CMDLINE_FILE" ]; then
    cat "$CMDLINE_FILE" >&2
    CMDLINE_CONTENTS=$(cat "$CMDLINE_FILE")
fi

echo "File: $CMDLINE_FILE (before)" >&2
echo "$CMDLINE_CONTENTS"

# remove duplicates, use xargs to trim leading and trailing spaces
CMDLINE_CONTENTS=$(echo "$CMDLINE_CONTENTS" | sed 's/cgroup_memory=[a-z0-9A-Z,]*//g' | xargs)
CMDLINE_CONTENTS=$(echo "$CMDLINE_CONTENTS" | sed 's/cgroup_enable=[a-z0-9A-Z,]*//g' | xargs)
CMDLINE_CONTENTS=$(echo "$CMDLINE_CONTENTS" | sed 's/enable_uart=[a-z0-9A-Z,]*//g' | xargs)

# append options
CMDLINE_CONTENTS=$(printf "%s %s" "$CMDLINE_CONTENTS" "cgroup_memory=1 cgroup_enable=memory")

# optional: enable_uart=1 (enabled), enable_uart=0 (disabled)
# or leave blank if no option should be specified
if [ -n "${RECIPE_PARAM_ENABLE_UART:-}" ]; then
    case "$RECIPE_PARAM_ENABLE_UART" in
        1|0)
            CMDLINE_CONTENTS=$(printf "%s %s" "$CMDLINE_CONTENTS" "enable_uart=$RECIPE_PARAM_ENABLE_UART")
            ;;
        *)
            echo "ERROR: Invalid enable_uart parameter value. Only accepts either '1' (enable) or '0' (disable)" >&2
            exit 1
            ;;
    esac
fi

printf '%s' "$CMDLINE_CONTENTS" > "$CMDLINE_FILE"

echo "File: $CMDLINE_FILE (after)" >&2
cat "$CMDLINE_FILE" >&2
