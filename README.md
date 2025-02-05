# Rugix thin-edge.io repository

**Additional recipes and layers for [Rugix](https://rugix.io).**

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

### Fail to bake image: raspios-tedge-pi5

The following command fails.

```sh
./run-bakery bake image raspios-tedge-pi5
```

**Output**

```sh
bash: warning: setlocale: LC_ALL: cannot change locale (C.UTF-8): No such file or directory
v0.8: Pulling from silitics/rugix-bakery
Digest: sha256:4061cd754bef23c58c1f4ca49b758c721ba16a1a64c860507aeb411518da79d5
Status: Image is up to date for ghcr.io/silitics/rugix-bakery:v0.8
 INFO baking image `raspios-tedge-pi5`
 INFO baking layer `raspios-tedge`
 INFO baking layer `raspios`
 INFO downloading `https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz`
 INFO decompressing XZ image
 INFO creating `.tar` archive with system files
 INFO Extracting layer.
 INFO [ 1/23] update package lists {}
 INFO     - 00-install.sh
Error: unable to mount /dev
├╴at crates/tools/rugix-bakery/src/oven/customize.rs:297:62
│   
╰─▶ unable to bind mount
    ├╴at /project/crates/libs/rugix-common/src/mount.rs:68:10
    ├╴dst: "/tmp/.tmpQZO7e9/roots/system/dev"
    ├╴src: "/dev"
    │   
    ╰─▶ ENOENT: No such file or directory
```