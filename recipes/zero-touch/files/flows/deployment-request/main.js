/**
 * deployment-request/main.js
 */

const utf8 = new TextDecoder("utf8");

export function onMessage(message, context) {
    const raw = utf8.decode(message.payload);
    if (raw.length === 0) {
        return [];
    }
    console.info(`Requested new deployment. info=${raw}`);
    let payload;
    try {
        payload = JSON.parse(raw);
    } catch (e) {
        console.error(`deployment-request: Failed to parse message. error=${e}`);
        return [];
    }

    // Set the target information from the input message
    // to indicate that the device's assignment to a group
    const {fragment, value} = payload.deployment || {};
    if (!fragment || !value) {
        console.warn(`Payload did not contain information about the deployment under .deployment.fragment and/or .deployment.value`);
        return [];
    }

    console.debug(`Received new deployment information. payload=${value}`)
    return [{
        topic: `te/device/main///twin/${fragment}`,
        payload: JSON.stringify({
            assignedAt: message.time.toISOString(),
            ...value,
        }),
        mqtt: {
            retain: true,
            qos: 1,
        },
    }];
}
