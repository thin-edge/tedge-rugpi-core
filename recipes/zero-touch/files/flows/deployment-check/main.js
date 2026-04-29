const utf8 = new TextDecoder("utf8");

/**
 * Sanitize a deployment group name to a safe fragment key, matching the Go
 * model.SanitizeGroupName() function: characters in `/\.:\s` are replaced with
 * `__` and leading/trailing underscores are stripped.
 */
function sanitizeGroupName(name) {
    return name.replace(/[/\\.:\s]+/g, '__').replace(/^_+|_+$/g, '');
}

export function onStartup(_time, context) {
    // send a message
    // mark the device to the assignment
    // but since we don't yet know the target, just leave it blank, but use the name assignment
    // so the server can pick up that this device will be contacting it
    // tedge mqtt pub -r te/device/main///twin/c8y_continuous_deployment_target '{"name": "default"}'
    return [{
        topic: `deployment-check/startup`,
        payload: JSON.stringify({
            name: context.config.group,
        }),
        mqtt: {
            qos: 1,
        },
    }];
}

export function onMessage(message, context) {
    const deployment = JSON.parse(utf8.decode(message.payload));

    // 204: no update available
    if (!deployment.target || !deployment.revisionId) {
        console.log("No update available");
        return [];
    }

    // Server-side throttle: back off gracefully, do not update the target assignment.
    if (deployment.retryAfterSeconds && deployment.retryAfterSeconds > 0) {
        console.log(`Server requested back-off. retryAfterSeconds=${deployment.retryAfterSeconds}`);
        return [];
    }

    // check if the deployment has already been seen
    const lastDeploymentID = context.flow.get("lastDeploymentRevisionId") || "";
    if (deployment.revisionId === lastDeploymentID) {
        // TODO: include more info here
        console.log(`Already seen deployment. revisionId=${deployment.revisionId}`);
        return [];
    }
    context.flow.set("lastDeploymentRevisionId", deployment.revisionId);

    const groupName = context.config.group || deployment.deploymentName || "default";
    const sanitized = sanitizeGroupName(groupName);

    return [
        // Publish on-change event
        {
            topic: "te/device/main///e/deployment",
            mqtt: { qos: 1 },
            payload: JSON.stringify({
                text: `New deployment. name=${deployment.deploymentName}, version=${deployment.deploymentVersion}`,
                deployment,
            }),
        },
        // Set target state in the per-group root fragment.
        // thin-edge.io maps this to a root-level Cumulocity fragment so that
        // independent group updates don't overwrite each other.
        {
            topic: `te/device/main///twin/c8y_continuous_deployment_target__${sanitized}`,
            mqtt: { qos: 1, retain: true },
            payload: JSON.stringify({
                assignedAt: message.time.toISOString(),
                bucketNumber: deployment.bucketNumber,
                name: deployment.deploymentName,
                version: deployment.deploymentVersion,
                target: deployment.target,
            }),
        },
    ];
}