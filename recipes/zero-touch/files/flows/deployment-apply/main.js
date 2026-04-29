const utf8 = new TextDecoder("utf8");

/**
 * Sanitize a deployment group name to a safe fragment key, matching the Go
 * model.SanitizeGroupName() function.
 */
function sanitizeGroupName(name) {
    return name.replace(/[/\\.:\s]+/g, '__').replace(/^_+|_+$/g, '');
}

function updateArtifactURL(url, c8y_proxy_client_host, c8y_proxy_client_port, updateArtifactURL) {
    if (/\/inventory\/binaries\//.test(url)) {
        // Rewrite the host/port to the local thin-edge.io c8y proxy so the device
        // can download binaries without needing direct Cumulocity access.
        // Uses plain regex rather than the WHATWG URL API, which is not part of
        // the ECMAScript spec and may not be available in the flow JS runtime.
        // FIXME: How to determine when to use http or https to access the local c8y proxy
        return url.replace(/^https?:\/\/[^/]+/, `${updateArtifactURL}://${c8y_proxy_client_host}:${c8y_proxy_client_port}/c8y`);
    }
    return url;
}

function convertToLocalDeviceProfileCommand(deployment, config) {
    const { c8y_proxy_client_host = "127.0.0.1", c8y_proxy_client_port = "8001", c8y_proxy_client_scheme = "http" } = config;
    const { name, version, target = {} } = deployment;
    const operations = [];

    if (target.firmware) {
        const { name: fwName, version: fwVersion, url } = target.firmware;
        operations.push({
            operation: "firmware_update",
            startedAt: (new Date()).getTime() / 1000,
            "@skip": false,
            payload: {
                name: fwName,
                version: fwVersion,
                remoteUrl: url,
                tedgeUrl: updateArtifactURL(url, c8y_proxy_client_host, c8y_proxy_client_port, c8y_proxy_client_scheme),
            },
        });
    }

    if (Array.isArray(target.software) && target.software.length > 0) {
        const byType = new Map();
        for (const ref of target.software) {
            const type = ref.softwareType ?? "default";
            if (!byType.has(type)) byType.set(type, []);
            byType.get(type).push({
                name: ref.name,
                version: ref.version,
                // Note: the server url is not preserved
                ...(ref.url ? { url: updateArtifactURL(ref.url, c8y_proxy_client_host, c8y_proxy_client_port, c8y_proxy_client_scheme) } : {}),
                action: "install",
            });
        }
        for (const [type, modules] of byType) {
            operations.push({
                operation: "software_update",
                "@skip": false,
                payload: {
                    updateList: [{ type, modules }],
                },
            });
        }
    }

    if (Array.isArray(target.configuration)) {
        for (const { url, ...cfg } of target.configuration) {
            operations.push({
                operation: "config_update",
                "@skip": false,
                payload: {
                    ...cfg,
                    ...(url ? { serverUrl: url } : {}),
                    ...(url ? { remoteUrl: updateArtifactURL(url, c8y_proxy_client_host, c8y_proxy_client_port, c8y_proxy_client_scheme) } : {}),
                },
            });
        }
    }

    return { status: "init", target, name, version, operations };
}

function isRolloutOperation(payload) {
    return !!payload.target;
}


export function onMessage(message, context) {

    const groupName = context.config.group || "";
    if (!groupName) {
        console.info("Group name not set. skipping");
        return [];
    }
    const sanitized = sanitizeGroupName(groupName);

    // Per-group root fragment keys (flat, no nesting — safe for concurrent Cumulocity PUTs).
    // Format: c8y_continuous_deployment_target__{sanitized}  /  c8y_continuous_deployment_state__{sanitized}
    const targetFragKey = `c8y_continuous_deployment_target__${sanitized}`;
    const stateFragKey  = `c8y_continuous_deployment_state__${sanitized}`;
    // Legacy single-group fragment names (kept for backward compatibility during migration).
    const legacyTargetFrag = `c8y_continuous_deployment_target`;
    const legacyStatusFrag = `c8y_continuous_deployment`;

    // on init message to set the initial assignment to the deployment group
    if (message.topic === "deployment-check/startup") {
        // TODO: check the state of the deployment as well, and 
        if (context.mapper.get("rollout:target")) {
            console.log("Ignore deployment-check/startup as the rollout is already known");
            return [];
        }
        console.log("[deployment-apply] Setting deployment target");
        return [{
            topic: `te/device/main///twin/${targetFragKey}`,
            payload: message.payload,
            mqtt: {
                qos: 1,
                retain: true,
            },
        }];
    }

    const parts = message.topic.split("/") || [];
    if (parts.length < 7) {
        console.log("Ignoring unexpected topics")
        return [];
    }

    const telemetryType = parts[5];
    const entityTopic = `te/device/main//`;

    const output = [];

    if (telemetryType == "twin") {
        // New per-group root format: c8y_continuous_deployment_state__{sanitized}
        const isNewStatus = parts[6] === stateFragKey;
        // Legacy single-group format: c8y_continuous_deployment
        const isLegacyStatus = parts[6] === legacyStatusFrag;
        if (isNewStatus || isLegacyStatus) {
            // store the current state in memory
            context.mapper.set("rollout:current", utf8.decode(message.payload));
            return output;
        }

        // New per-group root format: c8y_continuous_deployment_target__{sanitized}
        const isNewTarget = parts[6] === targetFragKey;
        // Legacy single-group target format: c8y_continuous_deployment_target
        const isLegacyTarget = parts[6] === legacyTargetFrag;
        // if not target state, then ignore it
        if (!isNewTarget && !isLegacyTarget) {
            console.debug(`ignoring unexpected message. topic=${message.topic}`);
            return output;
        }

        // Ignore stale retain messages as we're only interested in state changes!
        // as this message will be triggered when the mapper starts, so it isn't really
        // and indication that there is a new deployment
        if (message.mqtt.retain) {
            console.log(`Storing target state (from retain message). topic=${message.topic}`);
            context.mapper.set("rollout:target", utf8.decode(message.payload));
            return [];
        }

        //
        // twin update so created a new command
        //
        const deploymentTarget = JSON.parse(utf8.decode(message.payload));

        if (!deploymentTarget.target) {
            console.log(`Ignoring digital twin message as it does not include the target (maybe it was the init message)`);
            return output;
        }

        let currentState = {};
        try {
            currentState = JSON.parse(context.mapper.get("rollout:current") || "{}");
        } catch (e) {
            console.log(`Could not read current state. error=${e}`);
            currentState = {};
        }

        // TODO: Return if the current state equals the deployment state
        const isStateEqual = (current, target) => {
            if (current.status === "failed") {
                // failures should be retried
                return false;
            }
            return (current.name === target.name && current.version === target.version);
        };

        if (isStateEqual(currentState, deploymentTarget)) {
            console.log("Deployment state matches target state");
            return [];
        }

        console.log("Create an device profile operation", {
            current: currentState,
            target: deploymentTarget,
        });
        
        // const cmdTopic = `${entityTopic}/cmd/device_profile/rollout-${payload.name}-${message.time.getTime()}`;
        const cmdTopic = `${entityTopic}/cmd/device_profile/rollout-${deploymentTarget.name}-${deploymentTarget.version}`;

        const command = {
            mqtt: {retain: true, qos: 1},
            topic: cmdTopic,
            payload: JSON.stringify(convertToLocalDeviceProfileCommand(deploymentTarget, context.config)),
        };
        console.log("Creating command payload", command);
        output.push(command);

    } else if (telemetryType == "cmd" && parts[6] == "device_profile") {
        //
        // device profile command updates
        //

        const [_te, _e1, _e2, _e3, _e4, _cmd, _cmdName, cmdId] = parts;

        if (!cmdId.startsWith("rollout-")) {
            console.log(`Ignoring commands from another source. topic=${message.topic}, cmdId=${cmdId}`);
            return [];
        }

        const raw = utf8.decode(message.payload);
        if (raw.length === 0) {
            // operation is being cleared
            console.log(`Operation has been cleared. topic=${message.topic}`);
            return [];
        }
        const payload = JSON.parse(raw);

        if (!isRolloutOperation(payload)) {
            // not a rollout operation
            console.log(`Device profile doesn't look like an operation. topic=${message.topic}, cmdId=${cmdId}`);
            return [];
        }

        const currentStateTopic = `${entityTopic}/twin/${stateFragKey}`;

        const clearCommand = () => {
            output.push({
                topic: message.topic,
                mqtt: {retain: true, qos: 1},
                payload: "",
            });
        }

        const updateStatus = (state, properties = {}) => {
            console.log(`Updating rollout state. state=${state}`);
            output.push({
                topic: currentStateTopic,
                payload: JSON.stringify({
                    name: payload.name,
                    version: payload.version,
                    state,
                    updatedAt: message.time.toISOString(),
                    ...properties,
                }),
                mqtt: {retain: true, qos: 1},
            })
        }

        const getDurationInSeconds = () => {
            if (!payload.startedAt) {
                return 0;
            }
            const endedAt = (new Date()).getTime() / 1000;
            if (endedAt > payload.startedAt) {
                return endedAt - payload.startedAt;
            }
            return 0;
        };

        if (payload.status == "executing") {
            updateStatus("in_progress");
            output.push({
                topic: `${entityTopic}/e/rollout_progress`,
                payload: JSON.stringify({
                    text: `Applying rollout on device. name=${payload.name}, version=${payload.version}`,
                    details: payload,
                }),
            });
        } else if (payload.status == "successful") {
            updateStatus("ok");
            const duration = getDurationInSeconds();
            let text = `Rollout successful. name=${payload.name}, version=${payload.version}`;
            if (duration > 0) {
                text = `Rollout successful. name=${payload.name}, version=${payload.version}, duration=${duration}s`;
            }
            output.push({
                topic: `${entityTopic}/e/rollout_progress`,
                payload: JSON.stringify({
                    text,
                    duration,
                    details: payload,
                }),
            });
            clearCommand();
        } else if (payload.status == "failed") {
            const reason = payload.reason ?? "Unknown reason";
            const duration = getDurationInSeconds();
            updateStatus("failed", {
                reason,
            });
            let text = `Rollout failed. name=${payload.name}, version=${payload.version}, reason=${reason}`;
            if (duration > 0) {
                text = `Rollout failed. name=${payload.name}, version=${payload.version}, reason=${reason}, duration=${duration}s`;
            }
            output.push({
                topic: `${entityTopic}/e/rollout_progress`,
                payload: JSON.stringify({
                    text,
                    duration,
                    reason,
                    details: payload,
                }),
            });
            clearCommand();
        }
    } else {
        console.log("Unexpected message");
    }
    return output;
}