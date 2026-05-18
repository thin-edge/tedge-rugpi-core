#!/bin/sh
# deployment.sh — calls the /apply endpoint and emits the JSON response
# body on stdout (for the flow's onMessage handler).
#
# Usage: deployment.sh <group> [--version <version>] [--force]
#
# Exit codes:
#   0  — success (eligible: 201 body printed, or not-eligible: 204 no output)
#   1  — usage/configuration error
#   2  — HTTP request failed
set -e

DEPLOYMENT_GROUP=
DEPLOYMENT_VERSION=latest
FORCE_DEPLOYMENT=0
MAX_ATTEMPTS=${MAX_ATTEMPTS:-2}
COMMAND="${COMMAND:-apply}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --group)
            DEPLOYMENT_GROUP="$2"
            shift
            ;;
        --version)
            DEPLOYMENT_VERSION="$2"
            shift
            ;;
        --max-attempts)
            MAX_ATTEMPTS="$2"
            shift
            ;;
        --force)
            FORCE_DEPLOYMENT=1
            ;;
        --*|-*)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
        *)
            COMMAND="$1"
            ;;
    esac
    shift
done

if [ -z "$COMMAND" ]; then
    echo "Invalid usage. Please define a command to use. Supported commands: [check, apply]" >&2
    exit 1
fi

if [ -z "$DEPLOYMENT_GROUP" ]; then
    echo "No deployment group specified. Pass the group name as the first argument." >&2
    exit 1
fi

# Build context key=value lines that the server uses for selector matching.
get_context() {
    on_change=1
    if [ "$1" = "check" ]; then
        on_change=0
    fi
    OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    OS_VERSION_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
    ARCH=$(uname -m 2>/dev/null || true)

    echo "os_family: linux"
    [ -n "$OS_ID" ]              && echo "os_id: $OS_ID"
    [ -n "$OS_VERSION_CODENAME" ] && echo "os_version_codename: $OS_VERSION_CODENAME"
    [ -n "$ARCH" ]               && echo "arch: $ARCH"

    DEVICE_TYPE=$(tedge config get device.type 2>/dev/null || true)
    [ -n "$DEVICE_TYPE" ] && echo "device_type: $DEVICE_TYPE"

    IMAGE_UPDATE_TECH=not-supported
    if which rugix-ctrl >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=rugix
    elif which rauc >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=rauc
    elif which mender >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=mender
    fi
    echo "firmware_update_type: $IMAGE_UPDATE_TECH"

    FIRMWARE_INFO=$(find /usr/share/tedge-inventory/scripts.d/ -name "*_firmware" -exec {} \; 2>/dev/null ||:)
    if [ -n "$FIRMWARE_INFO" ]; then
        FIRMWARE_NAME=$(echo "$FIRMWARE_INFO" | grep '^name=' | cut -d= -f2 | tr -d '"')
        FIRMWARE_VERSION=$(echo "$FIRMWARE_INFO" | grep '^version=' | cut -d= -f2 | tr -d '"')
        [ -n "$FIRMWARE_NAME" ]    && echo "firmware_name: $FIRMWARE_NAME"
        [ -n "$FIRMWARE_VERSION" ] && echo "firmware_version: $FIRMWARE_VERSION"
    fi

    MODEL_INFO=$(find /usr/share/tedge-inventory/scripts.d/ -name "*_c8y_Hardware" -exec {} \; 2>/dev/null ||:)
    if [ -n "$MODEL_INFO" ]; then
        MODEL=$(echo "$MODEL_INFO" | grep '^model=' | cut -d= -f2 | tr -d '"')
        [ -n "$MODEL" ] && echo "model: $MODEL"
    fi

    # Report the currently running deployment version (only when state=ok) so
    # the server can suppress the operation when the device is already up-to-date,
    # or strip firmware from the operation when only software/config differs.
    SANITIZED_GROUP=$(echo "$DEPLOYMENT_GROUP" | sed 's|[/\\.:\t ]|__|g' | sed 's|^_*||;s|_*$||')
    STATE_TOPIC="te/device/main///twin/c8y_continuous_deployment_state__${SANITIZED_GROUP}"
    STATE_JSON=$(tedge mqtt sub "$STATE_TOPIC" -C 1 -W 1 --no-topic 2>/dev/null || true)

    TARGET_TOPIC="te/device/main///twin/c8y_continuous_deployment_target__${SANITIZED_GROUP}"
    TARGET_JSON=$(tedge mqtt sub "$TARGET_TOPIC" -C 1 -W 1 --no-topic 2>/dev/null || true)
    CURRENT_TARGET_VERSION=

    if [ -n "$STATE_JSON" ]; then
        CURRENT_STATE=$(echo "$STATE_JSON" | jq -r '.state // empty' 2>/dev/null || true)
        CURRENT_VERSION=$(echo "$STATE_JSON" | jq -r '.version // empty' 2>/dev/null || true)
        TOTAL_ATTEMPTS=$(echo "$STATE_JSON" | jq -r '.attempts // 0' 2>/dev/null || true)

        if [ -n "$TOTAL_ATTEMPTS" ]; then
            # include how many attempts have been made to the server
            echo "attempts: $TOTAL_ATTEMPTS"
        fi

        if [ -n "$TARGET_JSON" ]; then
            CURRENT_TARGET_VERSION=$(echo "$TARGET_JSON" | jq -r '.version // ""' 2>/dev/null || true)
        fi

        # Note: only check attempts if the target and current version are the same, otherwise
        # it will be a new deployment
        if [ "$FORCE_DEPLOYMENT" = 0 ]; then
            if [ "$on_change" = 1 ]; then
                if [ "$CURRENT_TARGET_VERSION" = "$CURRENT_VERSION" ] && [ "$TOTAL_ATTEMPTS" -gt "$MAX_ATTEMPTS" ]; then
                    echo "Skipping, as maximum number of attempts has been processed. attempts=$TOTAL_ATTEMPTS, max-attempts=$MAX_ATTEMPTS" >&2
                    return 1
                fi
            fi
        fi

        case "$CURRENT_STATE" in
            ok|failed)
                # not in progress — proceed
                ;;
            *)
                # in_progress or not yet started — signal caller to skip
                if [ "$on_change" = 1 ]; then
                    echo "Skipping, as deployment already in progress. state=$CURRENT_STATE" >&2
                    return 1
                fi
                ;;
        esac

        if [ "$CURRENT_STATE" = "ok" ] && [ -n "$CURRENT_VERSION" ]; then
            echo "deployment_version: $CURRENT_VERSION"
        fi
    fi
}

print_context() {
    {
        echo "============= DEVICE_CONTEXT ============="
        echo "${DEVICE_CONTEXT}"
        echo "=========================================="
    } >&2
}

# Call the /apply endpoint.
# tedge http returns the response body on stdout together with an exit code
# that reflects the HTTP status class (0 = 2xx success, non-zero = error).
# We use --fail-with-body so that non-2xx responses surface as errors while we
# still get the body for logging.
case "$COMMAND" in
    apply)
        DEVICE_CONTEXT=$(get_context change_only) || exit 0
        print_context
        QUERY_PARAMS="onUpdateOnly=true&trackedBy=agent"
        if [ "$FORCE_DEPLOYMENT" = 1 ]; then
            if [ -n "$QUERY_PARAMS" ]; then
                QUERY_PARAMS="${QUERY_PARAMS}&forceDeployment=true"
            else
                QUERY_PARAMS="forceDeployment=true"
            fi
        fi
        RESPONSE=$(tedge http post \
            "/c8y/service/gated-rollout-proxy/deployments/${DEPLOYMENT_GROUP}/versions/${DEPLOYMENT_VERSION}/apply?${QUERY_PARAMS}" \
            --data "$(printf '%s\n' "$DEVICE_CONTEXT")" \
            --content-type text/plain) || true
        ;;
    check)
        DEVICE_CONTEXT=$(get_context check) || exit 0
        print_context

        QUERY_PARAMS=
        if [ "$FORCE_DEPLOYMENT" = 1 ]; then
            if [ -n "$QUERY_PARAMS" ]; then
                QUERY_PARAMS="${QUERY_PARAMS}&forceDeployment=true"
            else
                QUERY_PARAMS="forceDeployment=true"
            fi
        fi
        RESPONSE=$(tedge http post \
            "/c8y/service/gated-rollout-proxy/deployments/${DEPLOYMENT_GROUP}/rollout?${QUERY_PARAMS}" \
            --data "$(printf '%s\n' "$DEVICE_CONTEXT")" \
            --content-type text/plain) || true
        ;;
esac


# A non-empty response indicates 201 Created (operation triggered).
# An empty/blank response means 204 No Content (not eligible).
if [ -n "$RESPONSE" ]; then
    echo "$RESPONSE"
fi
