# palo-check-gp-users

Fetch Palo Alto firewall GlobalProtect user details.

## Requirements

Installed packages: openssl, pan-python, xmlstarlet

## Telegraf exec script

Fetch known users and return data in XML format:

```xml
<?xml version="1.0"?>
<records>
  <entry>
    <session_id>1.2.3.4_1763669420</session_id>
    <username>bob</username>
    <status>active</status>
    <source_region>GB</source_region>
    <vpn_type>Device Level VPN</vpn_type>
    <tunnel_type>IPSec</tunnel_type>
    <client_os>Microsoft Windows 11 Pro , 64-bit</client_os>
    <app_version>6.2.8-223</app_version>
    <host_id>**********</host_id>
    <client_ip>1.2.3.4</client_ip>
    <disconnect_reason/>
    <cert_name>bob_vpn</cert_name>
    <login_epoch>1763669420</login_epoch>
    <logout_epoch>0</logout_epoch>
    <cert_expiry_epoch>1774603701</cert_expiry_epoch>
  </entry>
  <entry>
    <session_id>2.4.6.8_1763648254</session_id>
    <username>jane</username>
    <status>disconnected</status>
    <source_region>NL</source_region>
    <vpn_type>Device Level VPN</vpn_type>
    <tunnel_type>IPSec</tunnel_type>
    <client_os>Microsoft Windows 11 Pro , 64-bit</client_os>
    <app_version>6.3.2-525</app_version>
    <host_id>************</host_id>
    <client_ip>2.4.6.8</client_ip>
    <disconnect_reason>client logout</disconnect_reason>
    <login_epoch>1763648254</login_epoch>
    <logout_epoch>1763654978</logout_epoch>
    <duration_sec>6724</duration_sec>
    <cert_name>jane_vpn</cert_name>
    <cert_expiry_epoch>1774530841</cert_expiry_epoch>
  </entry>
  <entry>
    ...
  </entry>
</records>
```

- session_id: client_ip + "_" + login_epoch
- username
- status: connected / disconnected
- source_region: GeoIP code of client_ip
- tunnel_type: ip-sec / ssl
- vpn_type - Not completely sure what the options are, but "Device Level VPN" is returned for PC/Mac GP deployments.
- client_os: hip data
- app-version: GlobalProtect version
- host_id: hip data - UUID (missing for Linux clients older than v5.2)
- client_ip
- disconnect_reason: reason from previous-user (string)
- login-epoch: login-time-utc from current-user / previous-user
- logout-epoch: logout-time-utc from previous-user
- duration_sec: Duration of last connection from previous-user in seconds
- Optionally returned but always included in the XML:
  - cert-name: Name of the client certificate with a CN matching the username
  - cert-expiry-epoch: Expiry date of the client certificate

### CLI Usage

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
    -x path           Path to XSLT filters.        (default: /etc/panos/xsl)
    -g gateway        GlobalProtect gateway.       (default: all)
    -d domain         GlobalProtect domain.        (default: all)
    -c                Check client certs           (default: no)

    -h                Display this help and exit.
    -v                Verbose mode.
```

### Config file

Rather than parsing command-line details, a config file can be used. An example config file is included in this repository.

## Telegraf configuration/usage

Use Git to download the script, configuration file, and two XSL templates. Or download them individually as below.

Install the script to `/usr/local/sbin`:

`wget https://github.com/dmgeurts/palo-check-gp-users/raw/refs/heads/main/pan_chk_gp_users.sh`  
`chmod +x pan_chk_gp_users.sh`  
`sudo cp pan_chk_gp_users.sh /usr/local/sbin/` 

Create `/etc/panos/xsl` and populate it with a config file and the two XSL filters. Edit your config file as required.

`sudo mkdir -p /etc/panos/xsl`  
`wget https://github.com/dmgeurts/palo-check-gp-users/raw/refs/heads/main/pan_chk_gp_users.conf`  
`sudo cp pan_chk_gp_users.conf /etc/panos/<your preferred config name>`  
`sudo vi /etc/panos/<your preferred config name>` 

`wget https://github.com/dmgeurts/palo-check-gp-users/raw/refs/heads/main/xsl/process-users.xsl`  
`wget https://github.com/dmgeurts/palo-check-gp-users/raw/refs/heads/main/xsl/process-certs.xsl`  
`sudo cp process-*.xsl /etc/panos/xsl/` 

Then edit the Telegraf config and add a new `[[input.exec]]` section: 

```text
[...]

# Read GlobalProtect user metrics/details
[[inputs.exec]]
  ## Commands array
  commands = [ "/usr/local/sbin/pan_chk_gp_users.sh -k /etc/ipa/.panrc.fw01 /etc/panos/pan_chk_gp_users.fw01.conf" ]

  ## Run this script every 5 minutes, not every 10 seconds.
  interval = "5m"

  ## Set a specific timeout as API calls can take a little time, depending on how much data is collected and the CPU load of the firewall.
  timeout = "30s"

  ## Ignore Error Code
  # ignore_error = false (default)

  ## Data format
  # https://github.com/influxdata/telegraf/tree/master/plugins/parsers/xpath
  data_format = "xml"

  [[inputs.exec.xpath]]
    ## The metric name to store in InfluxDB
    metric_name = "'globalprotect_sessions'"

    ## The XPath query to select the data points (nodes)
    metric_selection = "/records/entry"

    ## TAGS: Used for grouping and filtering (Indexed)
    [inputs.exec.xpath.tags]
      ## Critical: Unique ID (Client IP + Login Time) prevents data overwrites
      session_id    = "session_id"

      ## User & Device Identifiers
      username      = "username"
      host_id       = "host_id"
      client_os     = "client_os"
      app_version   = "app_version"   # Tagged so you can group by version (e.g. Compliance)

      ## Connection Details
      status        = "status"        # 'active' or 'disconnected'
      source_region = "source_region"
      vpn_type      = "vpn_type"      # e.g. 'Device Level VPN'
      tunnel_type   = "tunnel_type"   # e.g. 'SSL'
      cert_name     = "cert_name"

    ## FIELDS: The actual data values (Not Indexed)
    [inputs.exec.xpath.fields]
      ## Integers/Numbers: Wrapped in number() so InfluxDB treats them as Values
      login_epoch       = "number(login_epoch)"
      logout_epoch      = "number(logout_epoch)"
      duration_sec      = "number(duration_sec)"      # Will be null for active users
      cert_expiry_epoch = "number(cert_expiry_epoch)"

      ## Strings: Information for display/tables
      client_ip         = "client_ip"
      disconnect_reason = "disconnect_reason"

[...]
```

Adjust as required.

Finally, reload Telegraf and monitor the journal for errors:

`sudo systemctl reload telegraf`  
`sudo journalctl -fu telegraf` 

⚠️ If using a `.panrc` api_key file, ensure that telegraf can read the file. ⚠️

One way to do so is to set the group ownership of this file to telegraf and permit read privileges to the group.

### Example flux queries

Active users: 

```js
from(bucket: "${bucket}") // Active users
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "globalprotect_sessions")
  |> filter(fn: (r) => r["status"] == "active")
  |> filter(fn: (r) => r["_field"] == "login_epoch")
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["_time"])
  |> distinct(column: "username")
  |> count()
  |> group()
  |> rename(columns: {_value: "Active users"})
```

Total users: 

```js
from(bucket: "${bucket}") // Total users
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "globalprotect_sessions")
  |> filter(fn: (r) => r["_field"] == "login_epoch")
  |> filter(fn: (r) => r["status"] == "disconnected")
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["_time"])
  |> distinct(column: "username")
  |> count()
  |> group()
  |> rename(columns: {_value: "Total users"})
```

Total client certificates: 

```js
from(bucket: "${bucket}") // Total client certificates
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "globalprotect_sessions")
  |> filter(fn: (r) => r["cert_name"] != "")
  |> filter(fn: (r) => r["_field"] == "cert_expiry_epoch")
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["_time"])
  |> distinct(column: "username")
  |> count()
  |> group()
  |> rename(columns: {_value: "Client Certs"})
```

Unused client certificates: 

```js
from(bucket: "${bucket}") // Unused client certificates
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "globalprotect_sessions")
  |> filter(fn: (r) => r["_field"] == "disconnect_reason")
  |> filter(fn: (r) => r["status"] == "unused")
  |> filter(fn: (r) => r["_value"] == "No session")
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["_time"])
  |> distinct(column: "cert_name")
  |> count()
  |> group()
  |> rename(columns: {_value: "Unused certs"})
```
