# palo-check-gp-users

Check Palo Alto firewall for user status.

## Telegraf exec script

Fetch known users, list in the following format

`user, active (current, last or never), login-time, logout-time, reason, client-ip, region, client, app-version, cert expiry

current/last login-time
last logout-time
last logout reason
current/last client-ip,region
current/last client (OS)

### Add check for user client certificate expiry
