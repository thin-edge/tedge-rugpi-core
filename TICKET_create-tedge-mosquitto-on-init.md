### Before tedge is initialized, the broker 

After thin-edge.io is installed and a cloud has not been connected, the mosquitto-conf folder is empty, and the mosquitto

```sh
/etc/tedge/mosquitto-conf
```

```sh
cat <<EOT > /etc/tedge/mosquitto-conf/tedge-mosquitto.conf
per_listener_settings true
connection_messages true
log_type error
log_type warning
log_type notice
log_type information
log_type subscribe
log_type unsubscribe
message_size_limit 268435455
listener 1883 0.0.0.0
allow_anonymous true
require_certificate false
EOT
```