# Rugix thin-edge.io repository

**Additional recipes and layers for [Rugix](https://oss.silitics.com/rugix/).**

To make the recipes and layers available, include the following in your `rugix-bakery.toml`:

```toml
[repositories]
tedge-rugix-core = { git = "https://github.com/thin-edge/tedge-rugix-core.git", branch = "v0.8-rugix" }
```

We follow [Cargo's flavor of semantic versioning](https://doc.rust-lang.org/cargo/reference/resolver.html#semver-compatibility).
You can also use the most recent development version by omitting the `branch` property.
Please be aware that this may break your builds if we introduce backwards-incompatible changes.

## Development

Rugix supports running an image in a VM to facilitate local development (without a device).

To start a local virtual machine, run the following commands:

1. Start the vm (this will build the system image if necessary)

    ```sh
    just start-vm
    ```

2. Open a new console (leaving the previous one running), and connect to the VM

    ```sh
    just connect-vm
    ```

## Known Issues

* After a firmware update, the tedge-agent does not accept a new firmware operations until it is restarted, as it is waiting for the previous operation to be cleared (possibly due to use `tedge reconnect c8y`)

    ```log
    Mar 09 09:46:55 rpi4-d83add90fe56 tedge-agent[831]: 2025-03-09T09:46:55.514655111Z  INFO tedge_agent::operation_workflows::actor: Waiting successful firmware_update operation to be cleared
    ```

If something does not work, then please create a ticket.
