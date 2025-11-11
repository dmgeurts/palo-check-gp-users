# palo-check-gp-users

Check Palo Alto firewall for user status.

## Telegraf exec script

Fetch known users, list in following format

`user, active (current or last), login-time, logout-time, reason, client-ip, region, client, app-version

current/last login-time
last logout-time
last logout reason
current/last client-ip,region
current/last client (OS)
