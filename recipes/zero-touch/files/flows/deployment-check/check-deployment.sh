#!/bin/sh
set -e
DEPLOYMENT_GROUP=
DEPLOYMENT_VERSION=
FORCE_DEPLOYMENT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            DEPLOYMENT_VERSION="$2"
            shift
            ;;
        --force)
            FORCE_DEPLOYMENT=1
            ;;
        --*|-*)
            echo "Unknown flag. $1" >&2
            exit 1
            ;;
        *)
            DEPLOYMENT_GROUP="$1"
            ;;
    esac
    shift
done

if [ -z "$DEPLOYMENT_VERSION" ]; then
    DEPLOYMENT_VERSION=latest
fi

if [ -z "$DEPLOYMENT_GROUP" ]; then
    echo "No DEPLOYMENT_GROUP is set. Set the deployment group and try again"
    exit 1
fi

get_context() {
    OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    ARCH=$(uname -m)

    OS_FAMILY="linux"
    echo "os_family: $OS_FAMILY"

    echo "os_id: $OS_ID"
    echo "os_version_codename: $OS_VERSION_CODENAME"
    echo "arch: $ARCH"

    DEVICE_TYPE=$(tedge config get device.type)
    echo "device_type: $DEVICE_TYPE"

    IMAGE_UPDATE_TECH=not-supported
    if which rugix-ctrl >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=rugix
    elif which rauc >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=rauc
    elif which rugix-ctrl >/dev/null 2>&1; then
        IMAGE_UPDATE_TECH=mender
    fi

    echo "firmware_update_type: $IMAGE_UPDATE_TECH"

    FIRMWARE_INFO=$(find /usr/share/tedge-inventory/scripts.d/ -name "*_firmware" -exec {} \; ||:)
    if [ -n "$FIRMWARE_INFO" ]; then
        FIRMWARE_NAME=$(echo "$FIRMWARE_INFO" | grep '^name=' | cut -d= -f2 | tr -d '"')
        FIRMWARE_VERSION=$(echo "$FIRMWARE_INFO" | grep '^version=' | cut -d= -f2 | tr -d '"')
        echo "firmware_name: $FIRMWARE_NAME"
        echo "firmware_version: $FIRMWARE_VERSION"
    fi

    MODEL_INFO=$(find /usr/share/tedge-inventory/scripts.d/ -name "*_c8y_Hardware" -exec {} \; ||:)
    if [ -n "$MODEL_INFO" ]; then
        MODEL=$(echo "$MODEL_INFO" | grep '^model=' | cut -d= -f2 | tr -d '"')
        echo "model: $MODEL"
    fi
}

DEVICE_CONTEXT=$(get_context)

{
    echo "============= DEVICE_CONTEXT ============="
    echo "${DEVICE_CONTEXT}"
    echo "=========================================="
} >&2

QUERY_PARAMS=""
if [ "$FORCE_DEPLOYMENT" = 1 ]; then
    QUERY_PARAMS="forceDeployment=true"
fi

tedge http post "/c8y/service/gated-rollout-proxy/deployments/${DEPLOYMENT_GROUP}/versions/${DEPLOYMENT_VERSION}/rollout?${QUERY_PARAMS}" \
    --data "$DEVICE_CONTEXT" \
    --content-type text/plain
