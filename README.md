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
    <username>bob</username>
    <active>yes</active>
    <current-count>1</current-count>
    <previous-count>1</previous-count>
    <login-time-utc>1763501590</login-time-utc>
    <logout-time-utc>1763498234</logout-time-utc>
    <reason>user session expired</reason>
    <tunnel-type>IPSec</tunnel-type>
    <vpn-type>Device Level VPN</vpn-type>
    <client-ip>1.2.3.4</client-ip>
    <source-region>GB</source-region>
    <client>Apple Mac OS X 26.0.1</client>
    <app-version>6.2.8-223</app-version>
    <cert-name>bob_the_builder_vpn</cert-name>
    <cert-expiry-epoch>2077518994</cert-expiry-epoch>
  </entry>
  <entry>
    ...
  </entry>
</records>
```

- username
- active: current-user = yes, previous-user = no
- login-time-utc: current-user otherwise from previous-user
- logout-time-utc
- reason (of logout)
- tunnel-type (ip-sec or ssl): current-user otherwise from previous-user
- vpn-type - Not completely sure what the options are, but "Device Level VPN" is returned for PC/Mac GP deployments.
- client-ip: current-user otherwise from previous-user
- source-region: current-user otherwise from previous-user
- client (OS): current-user otherwise from previous-user
- app-version: current-user otherwise from previous-user
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

  ## Run this script every 5 minutes, not every 10 seconds or so.
  interval = "5m"

  ## Set a specific timeout as API calls can take a little time, depending on how much data is collected and the CPU load of the firewall..
  timeout = "30s"

  ## Ignore Error Code
  # ignore_error = false (default)

  ## Data format
  # https://github.com/influxdata/telegraf/tree/master/plugins/parsers/xpath
  data_format = "xml"

  [[inputs.exec.xpath]]
    ## The metric name to store in InfluxDB
    metric_name = "'globalprotect_users'"

    ## The XPath query to select the data points (nodes)
    metric_selection = "/records/entry"

    ## TAGS: Used for grouping and filtering (Indexed)
    [inputs.exec.xpath.tags]
      username      = "username"
      source_region = "source-region"
      tunnel_type   = "tunnel-type"
      vpn_type      = "vpn-type"
      active        = "active"

    ## FIELDS: The actual data values (Not Indexed)
    [inputs.exec.xpath.fields]
      ## Integers/Numbers (Wrapped in number() to ensure they are not stored as strings)
      current_count     = "number(current-count)"
      previous_count    = "number(previous-count)"
      login_time_utc    = "number(login-time-utc)"
      logout_time_utc   = "number(logout-time-utc)"
      cert_expiry_epoch = "number(cert-expiry-epoch)"

      ## Strings
      client_ip   = "client-ip"
      reason      = "reason"
      client      = "client"
      app_version = "app-version"
      cert_name   = "cert-name"

[...]
```

Adjust as required.

Finally, reload Telegraf and monitor the journal for errors:

`sudo systemctl reload telegraf`  
`sudo journalctl -fu telegraf` 

⚠️ If using a `.panrc` api_key file, ensure that telegraf can read the file. ⚠️

One way to do so is to set the group ownership of this file to telegraf and permit read privileges to the group.
