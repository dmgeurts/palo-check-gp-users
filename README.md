# palo-check-gp-users

Fetch Palo Alto firewall GlobalProtect user details.

## Telegraf exec script

Fetch known users and return them in CSV format, listing the following details:

`CSV_HEADER=("username" "active" "login-time-utc" "logout-time-utc" "reason" "tunnel-type" "client-ip" "source-region" "client" "app-version" "cert-name" "cert-expiry-epoch")`

- username
- active: listed under current-user yes/no
- login-time-utc: current-user otherwise from previous-user
- logout-time-utc
- reason (of logout)
- tunnel-type (ip-sec or ssl): current-user otherwise from previous-user
- client-ip: current-user otherwise from previous-user
- source-region: current-user otherwise from previous-user
- client (OS): current-user otherwise from previous-user
- app-version: current-user otherwise from previous-user
- Optional:
  - cert-name: Name of the client certificate with a CN matching the username
  - cert-expiry-epoch: Expiry date of the client certificate

## Usage

```text
Usage: pan_chk_gp_users.sh [-hv] [OPTIONS] FQDN/PATH
This script returns current and previous GrobalProtect user details for use by Telegraf.
Optionally, it can add client certificate name and expiry.

Either of the following must be provided:
    FQDN              Fully qualified name of the Palo Alto firewall or Panorama
                      interface. It must be reachable from this host on port TCP/443.
    PATH              Path to config file.

OPTIONS:
    -k key(path|ext)  API key file location or extension. Default: /etc/ipa/.panrc
                      If a string is parsed, the following paths are searched:
                      {key(path)}/.panrc         - Example: /etc/panos/fw1.local/.panrc
                      /etc/ipa/.panrc.{key(ext)} - Example: /etc/ipa/.panrc.fw1.local
    -g gateway        GlobalProtect gateway.       (default: all)
    -d domain         GlobalProtect domain.        (default: all)
    -c                Check client certs           (default: no)

    -h                Display this help and exit.
    -v                Verbose mode.
```

## Config file

Rather than parsing command-line details, a config file can be used. An example config file is included in this repository.
