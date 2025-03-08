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

There are currently no known issues. If something does not work, then please create a ticket.
