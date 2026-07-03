/**
 * deployment-track/main.js
 *
 * Flow:
 *   1. This flow handles fragment tracking alongside thin-edge.io's execution:
 *      - On cmd/device_profile/{operationId} successful/failed: update state fragment
 *
 * Concurrency handling:
 *   Multiple device_profile commands for the same deployment group can be in flight
 *   simultaneously. A `failed` or `successful` terminal status is only published to
 *   the state twin fragment once ALL in-flight commands have settled. While at least
 *   one command is still executing the state remains `in_progress`.
 *
 *   context.mapper keys used (persisted at the mapper-process level, not per-invocation):
 *     rollout-track:inflight:{sanitized}       — JSON array of in-flight cmdIds
 *     rollout-track:attempts:{sanitized}       — total terminal events (successful + failed)
 *     rollout-track:failedAttempts:{sanitized} — failed terminal events only
 */

const utf8 = new TextDecoder("utf8");

const KEY_NS = 'rollout-track';

/**
 * Sanitize a deployment group name to a safe fragment key, matching the Go
 * model.SanitizeGroupName(): characters in `/\.:\s` → `__`, leading/trailing `_` stripped.
 */
function sanitizeGroupName(name) {
    return name.replace(/[/\\.:\s]+/g, '__').replace(/^_+|_+$/g, '');
}

// ---------------------------------------------------------------------------
// In-flight set helpers (stored in context.mapper as JSON arrays)
// ---------------------------------------------------------------------------

function getInflightSet(sanitized, context) {
    const raw = context.mapper.get(`${KEY_NS}:inflight:${sanitized}`);
    if (!raw) return new Set();
    try {
        return new Set(JSON.parse(raw));
    } catch {
        return new Set();
    }
}

function setInflightSet(sanitized, set, context) {
    context.mapper.set(`${KEY_NS}:inflight:${sanitized}`, JSON.stringify([...set]));
}

function getCounter(sanitized, name, context) {
    const raw = context.mapper.get(`${KEY_NS}:${name}:${sanitized}`);
    return raw ? (parseInt(raw, 10) || 0) : 0;
}

function incrementCounter(sanitized, name, context) {
    const val = getCounter(sanitized, name, context) + 1;
    context.mapper.set(`${KEY_NS}:${name}:${sanitized}`, String(val));
    return val;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export function onMessage(message, context) {
    const topic = message.topic;
    const raw = utf8.decode(message.payload);

    // Local device_profile command status (translated by thin-edge.io)
    const parts = topic.split("/");
    if (parts.length >= 8 && parts[5] === "cmd" && parts[6] === "device_profile") {
        return handleCommandStatus(topic, parts[7], raw, context);
    }

    return [];
}

// ---------------------------------------------------------------------------
// cmd/device_profile/{cmdId} status handler
// ---------------------------------------------------------------------------

function handleCommandStatus(topic, cmdId, raw, context) {
    // Empty payload means the retained command message was cleared by the
    // deployment-apply flow after it already processed the terminal status.
    // By that point the cmdId has already been removed from the inflight set,
    // so there is nothing to do here.
    if (raw.length === 0) {
        return [];
    }

    let payload;
    try {
        payload = JSON.parse(raw);
    } catch (e) {
        return [];
    }

    const [deploymentName, deploymentVersion] = `${payload.name}`.split("@");
    if (!deploymentName || !deploymentVersion) {
        console.info(`Ignoring profile update as it does not contain deployment info within the profile name. name=${payload.name}, expected=<name>@<version>`);
        return [];
    }
    const sanitized = sanitizeGroupName(deploymentName);
    const stateFragKey = `c8y_continuous_deployment_state__${sanitized}`;
    const now = new Date().toISOString();

    // Reset counters and in-flight set when the deployment version changes.
    const trackedVersion = context.mapper.get(`${KEY_NS}:version:${sanitized}`);
    if (trackedVersion !== deploymentVersion) {
        context.mapper.set(`${KEY_NS}:version:${sanitized}`, deploymentVersion);
        context.mapper.set(`${KEY_NS}:attempts:${sanitized}`, "0");
        context.mapper.set(`${KEY_NS}:failedAttempts:${sanitized}`, "0");
        setInflightSet(sanitized, new Set(), context);
    }

    const output = [];

    const updateState = (state, extra = {}) => {
        output.push({
            topic: `te/device/main///twin/${stateFragKey}`,
            mqtt: { retain: true, qos: 1 },
            payload: JSON.stringify({
                name: deploymentName,
                version: deploymentVersion,
                state,
                updatedAt: now,
                ...extra,
            }),
        });
    };

    const inflight = getInflightSet(sanitized, context);

    if (payload.status === "init") {
        // init: register in in-flight set but don't publish a state update yet
        inflight.add(cmdId);
        setInflightSet(sanitized, inflight, context);
    } else if (payload.status === "successful") {
        inflight.delete(cmdId);
        setInflightSet(sanitized, inflight, context);
        const attempts = incrementCounter(sanitized, 'attempts', context);
        const failedAttempts = getCounter(sanitized, 'failedAttempts', context);
        // Only emit 'ok' when every in-flight command has settled
        if (inflight.size === 0) {
            updateState("ok", { attempts, failedAttempts });
        }
    } else if (payload.status === "failed") {
        inflight.delete(cmdId);
        setInflightSet(sanitized, inflight, context);
        const attempts = incrementCounter(sanitized, 'attempts', context);
        const failedAttempts = incrementCounter(sanitized, 'failedAttempts', context);
        // Only emit 'failed' when no other commands are still running
        if (inflight.size === 0) {
            const reason = payload.reason ?? "Unknown";
            updateState("failed", { reason, attempts, failedAttempts });
        } else {
            console.info(`Command ${cmdId} failed but ${inflight.size} other command(s) still in flight for group '${deploymentName}'. Keeping state as in_progress.`);
        }
    } else {
        // Any other status (executing, etc.) is in-progress; register in in-flight set
        inflight.add(cmdId);
        setInflightSet(sanitized, inflight, context);
        const attempts = getCounter(sanitized, 'attempts', context);
        const failedAttempts = getCounter(sanitized, 'failedAttempts', context);
        updateState("in_progress", { attempts, failedAttempts });
    }

    return output;
}
