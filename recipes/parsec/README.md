# Parsec notes

**Pre-requisites**

The following is only supported on Debian Trixie!

1. Install the packages

    ```sh
    apt-get install -y parsec-service parsec-tool softhsm2
    ```

1. Initialize the slot (running as root)

    ```sh
    softhsm2-util --init-token --slot 0 --label "tedge" --pin 123456 --so-pin 123456
    ```

1. Get the slot number of the token of the created token

    ```sh
    softhsm2-util --show-slots
    ```

1. Modify the ownership of the token (so that parsec can interact with it):

    ```sh
    chown -R parsec:softhsm /var/lib/softhsm/tokens/*
    ```

    Alternatively, the token could be created using the parsec user, however it would involve creating a dedicate softhsm2.conf file which tells where the tokens should be stored.

1. Edit the parsec config.toml

    ```sh
    /etc/parsec/config.toml
    ```

    And the following pkcs11 provider configuration (using the slot_number from the previous step)

    ```toml
    [[provider]]
    name = "pkcs11-provider"
    provider_type = "Pkcs11"
    key_info_manager = "sqlite-manager"

    library_path = "/usr/lib/softhsm/libsofthsm2.so"
    slot_number = 1941414278
    user_pin = "123456"
    ```

1. Restart the service

    ```sh
    systemctl restart parsec
    ```

1. Create a newkey

    ```sh
    parsec-tool -p 2 create-ecc-key --key-name "tedge"
    ```

    **Note**

    Make sure the `-p <provider_num>` is set to the correct number associated to the pkcs11 provider. You can get the provider id using:

    ```sh
    parsec-tool list-providers
    ```

    The provider id is displayed in hexadecimal, so `0x02` should just be given to the `-p` flag as `2` (without the `0x` prefix, and removing any leading zeroes).

## Creating a key

```sh
parsec-tool -p 2 create-ecc-key --key-name "tedge"
```

## Create CSR

```sh
parsec-tool -p 2 create-csr --key-name tedge
```


## List all objects on a slot

```
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so -l -O --slot 1941414278
```
