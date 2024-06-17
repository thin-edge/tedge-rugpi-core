# Rugpi thin-edge.io repository

**Additional recipes and layers for [Rugpi](https://rugpi.io).**

To make the recipes and layers available, include the following in your `rugpi-bakery.toml`:

```toml
[repositories]
tedge-rugpi-core = { git = "https://github.com/thin-edge/tedge-rugpi-core.git", branch = "v0.7" }
```

We follow [Cargo's flavor of semantic versioning](https://doc.rust-lang.org/cargo/reference/resolver.html#semver-compatibility).
You can also use the most recent development version by omitting the `branch` property.
Please be aware that this may break your builds if we introduce backwards-incompatible changes.
