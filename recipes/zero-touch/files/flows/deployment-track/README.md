
## Bugs

### multiple in-process operations

The tracker can get out of sync if there are multiple operations being processed as the same time, as the next operation can start to be in-progress before the other command is marked as failed.

```
# tedge mqtt sub 'te/device/main///twin/c8y_continuous_deployment_state__zone0'
[te/device/main///twin/c8y_continuous_deployment_state__zone0] {"name":"zone0","version":"1.0.6","state":"failed","updatedAt":"2026-05-07T21:16:53.513Z","reason":"Device profile application failed"}
[te/device/main///twin/c8y_continuous_deployment_state__zone0] {"name":"zone0","version":"1.0.6","state":"in_progress","updatedAt":"2026-05-07T21:21:53.682Z"}
[te/device/main///twin/c8y_continuous_deployment_state__zone0] {"name":"zone0","version":"1.0.6","state":"failed","updatedAt":"2026-05-07T21:21:53.736Z","reason":"Device profile application failed"}
```

Possible solution

monitor sub operations (this would require tracking all operations, and keeping track of the command id of the parent operation) and filtering on the command id, and treating the "status" updates as re-publishing of the original operation. Below shows an example of the sub operation

```sh
[te/device/main///cmd/software_update/sub:device_profile:c8y-mapper-54506004] {
    "@version": "builtin",
    "logPath": "/var/log/tedge/agent/workflow-device_profile-c8y-mapper-54506004.log",
    "resumed_at": "1778188322.0",
    "status": "executing",
    "updateList": [
        {
            "modules": [
                {
                    "action": "install",
                    "name": "tree",
                    "version": "latest"
                },
                {
                    "action": "install",
                    "name": "bad-package",
                    "url": "https://bad.com/",
                    "version": "1.0"
                }
            ],
            "type": "apt"
        },
        {
            "modules": [
                {
                    "action": "install",
                    "name": "local/log-surge",
                    "url": "http://127.0.0.1:8001/c8y/inventory/binaries/6553455009",
                    "version": "2.0.0"
                },
                {
                    "action": "install",
                    "name": "local/certificate-alert",
                    "url": "http://127.0.0.1:8001/c8y/inventory/binaries/8753455008",
                    "version": "2.0.0"
                }
            ],
            "type": "flow"
        },
        {
            "modules": [
                {
                    "action": "install",
                    "name": "nodered",
                    "url": "http://127.0.0.1:8001/c8y/inventory/binaries/42704680",
                    "version": "4.0.3-22-minimal-docker"
                }
            ],
            "type": "container-group"
        }
    ]
}
```




## Problem description: incorrect state is published when multiple device profile commands are published


Currently the thin-edge.io [flow](flows/deployment-track/main.js), subscribes to the `te/device/main///cmd/device_profile/+` topic, and the flow publishes the current "state" of the deployment (of the device profile) is published to `c8y_continuous_deployment_state__${name}`, however the problem is that the current state might not always shown that there is an in-progress device profile command if multiple device profile commands are being processed sequentially; the following sequence shows the sequence which leads to the problem show that the deployment state is marked as "failed" instead of "in_progress".

1. device profile command 1 is set to executing
2. device profile command 2 is set to executing
3. device profile command 2 is set to failed

This causes a problem as there is another flow, flows/deployment-request/flow.toml, which check if there is already an in-progress commands and avoids sending an api request in such event, but since the in-progress state is sometimes incorrect, then it results in another device profile command being created (which results in another device profile command, which is created by the server).

Useful links / documentation
* thin-edge.io flows reference guide, https://thin-edge.github.io/thin-edge.io/references/mappers/flows/
* tedge-flows-examples; https://github.com/thin-edge/tedge-flows-examples


Potential solutions:

We might need to use the `context.mapper` to keep a count of how many in-progress operations, and then decrement it over time once the command completes, though be aware the context.mapper is not persisted across a restart of the tedge-mapper. It might still be worthwhile to create some events to indicate a failure attempt at least, whilst still showing something is in-progress, but doesn't affect the overall state indicator in the `c8y_continuous_deployment_state__${name}`. Though it might be useful to have an attempt counter, so that this information could also be forwarded to the server in the `deployment-request` flow, or even just do a locally check, "if attempt >= threshold then don't send the api request to the server".

Please create a proposal to fix the issue and a detailed plan.
