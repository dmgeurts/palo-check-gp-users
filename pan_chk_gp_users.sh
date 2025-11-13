#!/bin/bash
# Fetch GlobalProtect user details, parse output in Telegraf readable format

# This script uses the PanOS API to fetch Global Protect user details:
# - Current Users:
#   - All users: <show><global-protect-gateway><current-user/></global-protect-gateway></show>
#   - Or by gateway: <show><global-protect-gateway><current-user><gateway>$GATEWAY</gateway></current-user></global-protect-gateway></show>
#   - Or by domain: <show><global-protect-gateway><current-user><domain>$DOMAIN</domain></current-user></global-protect-gateway></show>
# - Previous Users
#   - All users: <show><global-protect-gateway><previous-user/></global-protect-gateway></show>
#   - Or by gateway: <show><global-protect-gateway><previous-user><gateway>$GATEWAY</gateway></previous-user></global-protect-gateway></show>
#   - Or by domain: <show><global-protect-gateway><previous-user><domain>$DOMAIN</domain></previous-user></global-protect-gateway></show>
# - (Optionally) Client Certificates: /config/shared/certificate/entry[contains(@name, '$CRT_FLT' )]
 # - Statistics:
 #   - <show><global-protect-gateway><statistics/></global-protect-gateway></show>
 #     - Shows total current and previous users with a gateway/domain breakdown.
 #   - <show><global-protect-gateway><summary><detail/></summary></global-protect-gateway></show>
 #     - Shows gateway summary: current-user, error-no-config, gateway-max-concurrent-tunnel, gateway-successful-ip-sec-connections, successful-gateway-connections, error-invalid-cookie, error-dup-user, gateway-successful-sslvpn-connections

## Requirements
# Installed packages: openssl, pan-python, xmlstarlet

## Fixed variables
# Reuse pan_instcert API key
API_KEY="/etc/ipa/.panrc"
# Filter for selecting certificates to report on
CRT_FLT="_vpn"
# Check client certs?
CHK_CERTS=false
# Script vars
VERBOSE=0
OPTIND=1

## Logging
LOG="/var/log/pan_chk_gp_users.log"
wlog() {
    printf "$*"
    printf "[$(date --rfc-3339=seconds)]: $*" >> "$LOG"
}
trap 'wlog "ERROR - Check GP users failed.\n"' TERM HUP

## Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-hv] [OPTIONS] FQDN/PATH
This script checks whether any certificates will expire within x days on a Palo Alto firewall
or Panorama.

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
EOF
}

## Read/interpret optional arguments
while getopts k:g:d:cvh opt; do
    case $opt in
        k)  API_KEY=$OPTARG
            ;;
        g)  GP_GATEWAY=$OPTARG
            ;;
        d)  GP_DOMAIN=$OPTARG
            ;;
        c)  CHK_CERTS=true
            ;;
        v)  VERBOSE=$((VERBOSE+1))
            ;;
        h)  show_help
            exit 0
            ;;
        *)  show_help >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"   # Discard the options and sentinel --

## Start logging
# Check if the log file can be written.
if [[ -w "$LOG" ]]; then
    # Write first line to log.
    wlog "START of pan_chk_certs.\n"
else
    echo "ERROR: Can't write to log file: $LOG. Sudo or root expected."
    exit 1
fi

## Host checks
PAN_MGMT=""
chk_host() {
    if grep -q -P '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}\.)+[a-zA-Z]{2,63}$)' <<< "$1"; then
        echo "$1"
        # Convert to lowercase
        local _host="${1,,}"
        if ! nc -z $_host 443 2>/dev/null; then
            wlog "ERROR: Palo Alto device unreachable at: https://$_host/\n"
            exit 4 
        fi
        PAN_MGMT="$_host"
        return 0 # Success / true
    else
        wlog "ERROR: '$1' is not a valid FQDN/hostname format.\n"
        # If the format is wrong, exit the script as it can't proceed
        return 1 # Failed / false
    fi
}

## Read key value from file
read_cfg() {
    local _key=$1
    local _file=$2
    local _value=$(grep -P "^${_key}=" "$_file" | sed -E "s/^${_key}=\"?(.*)\"?/\1/")
    if [[ -n "$_value" ]]; then
        echo "$_value"
        return 0 # true
    else
        return 1 # false
    fi
}

# Check whether a file path or a single valid FQDN was parsed for the Palo Alto API interface
CFG_FILE=""
if [[ -f "$@" ]]; then
    if [[ -r "$@" ]]; then
        CFG_FILE="$@"
        (( $VERBOSE > 0 )) && wlog "CFG_FILE: $CFG_FILE\n"
    else
        wlog "ERROR: File cannot be read: $@\n"
        exit 4
    fi        
    #(( $VERBOSE > 0 )) && wlog "File exists and can be read: $@\n"
elif chk_host "$@"; then
    # PAN_MGMT is now set and tested as reachable
    (( $VERBOSE > 0 )) && wlog "Host $PAN_MGMT is reachable.\n"
else
    wlog "ERROR: A valid configuration file (PATH) or FQDN is required to check GlobalProtect users.\n"
    wlog "Parsed string: $@\n\n"
    show_help >&2
    exit 4
fi

# Use parsed API key if given
if [[ "$API_KEY" != "/etc/ipa/.panrc" ]]; then
    if [ -d "API_KEY" ]; then
        # Parsed string is a directory
        API_KEY="${API_KEY}/.panrc"
    elif [[ "$API_KEY" != *\/* ]]; then
        # Parsed string is a file extension
        API_KEY="/etc/ipa/.panrc.$API_KEY"
    fi
    if [ -f "$API_KEY" ]; then
        : #wlog "Parsed API key file exists: $API_KEY\n"
    else
        wlog "ERROR: Parsed API key file doesn't exist: $API_KEY\n"
        show_help >&2
        exit 1
    fi
fi 
# Try to read API_KEY from file
if API_KEY=$(read_cfg "api_key" "$API_KEY"); then
    # Changes the variable from a file-path to the API KEY string
    (( $VERBOSE > 0 )) && wlog "API key read from file: $API_KEY\n"
fi

# Read config file
if [ -n "$CFG_FILE" ]; then
    # Verify a hostname is included in the config file
    if HOST=$(read_cfg "host" "$CFG_FILE"); then
        if chk_host "$HOST"; then
            # PAN_MGMT is now set and tested as reachable
            (( $VERBOSE > 0 )) && wlog "Host $PAN_MGMT found in $CFG_FILE is reachable.\n"
        else
            # Error is already logged
            exit 4
        fi
    else
        wlog "ERROR: Missing 'host=' entry in in: $CFG_FILE\n"
        exit 5
    fi
    # Try to read API key from config file if one isn't parsed with -k
    if [[ "$API_KEY" == "/etc/ipa/.panrc" ]] && API_KEY=$(read_cfg "api_key" "$CFG_FILE"); then
        (( $VERBOSE > 0 )) && wlog "API key found in: $CFG_FILE\n"
    fi
    # Try to read a GP Gateway from the config file if not parsed with -g
    if [ -z "$GP_GATEWAY" ] && GP_GATEWAY=$(read_cfg "gp_gateway" "$CFG_FILE"); then
        (( $VERBOSE > 0 )) && wlog "GlobalProtect Gateway \"$GP_GATEWAY\" filter found in: $CFG_FILE\n"
    elif [ -n "$GP_GATEWAY" ]; then
        (( $VERBOSE > 0 )) && wlog "GlobalProtect Gateway filter set to: $GP_GATEWAY\n"
    else
        (( $VERBOSE > 0 )) && wlog "Not filtering by GlobalProtect Gateway.\n"
    fi
    # Try to read a GP Domain from the config file if not parsed with -d
    if [ -z "$GP_DOMAIN" ] && GP_DOMAIN=$(read_cfg "gp_domain" "$CFG_FILE"); then
        (( $VERBOSE > 0 )) && wlog "GlobalProtect Domain \"$GP_DOMAIN\" filter found in: $CFG_FILE\n"
    elif [ -n "$GP_DOMAIN" ]; then
        (( $VERBOSE > 0 )) && wlog "GlobalProtect Gateway filter set to: $GP_DOMAIN\n"
    else
        (( $VERBOSE > 0 )) && wlog "Not filtering by GlobalProtect Domain.\n"
    fi
    # Try to read certificate expiry threshold from config file with -t
    if [[ ! "$CHK_CERTS" == "true" ]] && CHK_CERTS=$(read_cfg "chk_client_certs" "$CFG_FILE"); then
        if [[ "$CHK_CERTS" == "true" ]]; then
            (( $VERBOSE > 0 )) && wlog "Checking client certificates.\n"
        else
            (( $VERBOSE > 0 )) && wlog "Not checking client certificates.\n"
        fi
    fi
fi

# Throw an error if an API_KEY is not yet found
if [[ "$API_KEY" == "/etc/ipa/.panrc" ]]; then
    wlog "ERROR: No API KEY parsed and/or found.\n"
    show_help >&2
    exit 1
fi

# Sanity check, at least one host must be known
if [ -z "$PAN_MGMT" ]; then
    wlog "ERROR: No host found, terminating.\n"
    exit 1
fi
if [[ "$API_KEY" == "/etc/ipa/.panrc" ]]; then
    wlog "ERROR: No API key found. Parse option '-k', check the config file or $API_KEY\n"
    exit 5
fi

## Fetch GlobalProtect user details using panxapi.py
# Define the keys we want to extract
declare -a CURR_U_KEYS=("login-time-utc" "tunnel-type" "client-ip" "source-region" "client" "app-version")   # active=yes if user is returned
declare -a PREV_U_KEYS=("login-time-utc" "logout-time-utc" "reason" "client-ip" "source-region" "client" "app-version")  # active=no if user not active now
# client = OS identifier string

# Define all possible keys for the final CSV output, in desired order
declare -a CSV_HEADERS=("username" "active" "login-time-utc" "logout-time-utc" "reason" "tunnel-type" "client-ip" "source-region" "client" "app-version" "cert-name" "cert-expiry-epoch")

# Define a variable to hold all generated associative array names
declare -a USER_ARRAYS=()

# Function to run the panxapi command and get the raw XML
# Use 'grep -v' to filter out the status lines panxapi.py prints to stdout
get_api_xml() {
    local _cmd_xml=$1
    # Check if this is a config query (starts with '/') or op query (starts with '<')
    if [[ "$_cmd_xml" == "/"* ]]; then
        panxapi.py -h "$PAN_MGMT" -K "$API_KEY" -gx "$command_xml" 2>/dev/null | grep -v 'get: success'
    else
        panxapi.py -h "$PAN_MGMT" -K "$API_KEY" -xo "$command_xml" 2>/dev/null | grep -v 'op: success'
    fi
}

## Fetch data
if [[ -n "$GP_GATEWAY" ]]; then
    xml_sub="><gateway>$GP_GATEWAY</gateway>"
elif [[ -n "$GP_DOMAIN" ]]; then
    xml_sub="><domain>$GP_DOMAIN</domain>"
else
    xml_sub=""
fi
# Execute get_xml_api() and save the output to temp files
wlog "Fetching Current User data.\n"
TMP_CURR=$(mktemp)
if ! get_api_xml "<show><global-protect-gateway><current-user>$xml_sub</current-user></global-protect-gateway></show>" > "$TMP_CURR"; then
    wlog "ERROR: Failed to retrieve Current User XML data. Check API KEY validity and privileges.\n" >&2
    rm "$TMP_CURR"
    exit 1
fi
wlog "Fetching Previous User data.\n"
TMP_PREV=$(mktemp)
if ! get_api_xml "<show><global-protect-gateway><previous-user>$xml_sub</previous-user></global-protect-gateway></show>" > "$TMP_PREV"; then
    wlog "ERROR: Failed to retrieve Previous User XML data. Check API KEY validity and privileges.\n" >&2
    rm "$TMP_PREV"
    exit 1
fi
if [[ "$CHK_CERTS" == "true" ]]; then
    wlog "Fetching client certificate data.\n"
    TMP_CERT=$(mktemp)
    if ! get_api_xml "/config/shared/certificate/entry[contains(@name, '$CRT_FLT' )]" > "$TMP_CERTS"; then
        wlog "ERROR: Failed to retrieve client certificate data. Check API KEY validity and privileges.\n" >&2
        rm "$TMP_CERT"
        exit 1
    fi
fi

# Process 'Previous User' data first
wlog "Processing Previous Users (historical data).\n"
for username in $(xmlstarlet sel -t -v "//entry/username" "$TMP_PREV"); do
    # Sanitise the username for use in a bash variable name
    SAFE_UID=$(echo "$username" | tr '@%.=' '_')
    ARRAY_NAME="user_${SAFE_UID}_data"
    # Check if this user was already processed (from the current users list)
    if [[ ! -v "$ARRAY_NAME" ]]; then
        declare -gA "$ARRAY_NAME"
        USER_ARRAYS+=("$ARRAY_NAME")
    fi
    declare -n current_array_ref="$ARRAY_NAME"
    (( $VERBOSE > 0 )) && wlog "Processing user: $username"
    current_array_ref["username"]="$username"
    current_array_ref["active"]="no"
    for key in "${PREV_U_KEYS[@]}"; do
        value=$(xmlstarlet sel -t -v "//entry[username='$username']/$key" "$TMP_PREV")
        current_array_ref["$key"]="$value"
    done
done

# Next process 'Current User' data, overwriting any duplicate keys
wlog "Processing Current Users (live data).\n"
# Iterate over entries in temp XML file with xmlstarlet
for username in $(xmlstarlet sel -t -v "//entry/username" "$TMP_CURR"); do
    # Sanitise the username for use in a bash variable name
    SAFE_UID=$(echo "$username" | tr '@%.=' '_')
    ARRAY_NAME="user_${SAFE_UID}_data"
    # Create the array structure if it doesn't yet exist
    if [[ ! -v "$ARRAY_NAME" ]]; then
        declare -gA "$ARRAY_NAME"
        USER_ARRAYS+=("$ARRAY_NAME")
    fi
    declare -n current_array_ref="$ARRAY_NAME"
    (( $VERBOSE > 0 )) && wlog "Processing user: $username"
    current_array_ref["username"]="$username"
    current_array_ref["active"]="yes"  # Overwrite to 'yes' if username appears in both queries
    # Iterate through defined keys, overwriting duplicates
    for key in "${CUR_U_KEYS[@]}"; do
        value=$(xmlstarlet sel -t -v "//entry[username='$username']/$key" "$TMP_CURR")
        # Value might be empty if a field isn't present in the active list XML
        if [[ -n "$value" ]]; then
            current_array_ref["$key"]="$value"
        fi
    done
done

# Finally, process Certificates to add the certificate name in PanOS config and expiry date
if [[ "$CHK_CERTS" == "true" ]]; then
    wlog "Processing Certificates (Link CN to username).\n"
    # Iterate through certificate entries
    for cert_name in $(xmlstarlet sel -t -v "//entry/@name" "$TMP_CERT"); do
        # Get common-name and expiry-epoch for this certificate entry
        cn=$(xmlstarlet sel -t -v "//entry[@name='$cert_name']/common-name" "$TMP_CERT")
        expiry=$(xmlstarlet sel -t -v "//entry[@name='$cert_name']/expiry-epoch" "$TMP_CERT")
        # Try to find a user record that matches this common name
        if [[ -n "$cn" ]]; then
            SAFE_UID=$(echo "$cn" | tr '@%.=' '_')
            ARRAY_NAME="user_${SAFE_UID}_data"
            if [[ -v "$ARRAY_NAME" ]]; then
                # User found! Add cert details to their record
                declare -n current_array_ref="$ARRAY_NAME"
                current_array_ref["cert-name"]="$cert_name"
                current_array_ref["cert-expiry-epoch"]="$expiry"
            fi
        fi
    done
fi

# Clean up temp files
rm "$TMP_CURR" "$TMP_PREV" "$TMP_CERT"

## CSV output for Telegraf exec processing
wlog "Generating CSV Output, one line per user.\n"
# Print the header row
(IFS=,; echo "${CSV_HEADERS[*]}")
# Iterate through the collected user arrays and print data rows
for array_name in "${USER_ARRAYS[@]}"; do
    declare -n current_array="$array_name"
    # Build a single line for the current user
    LINE=""
    for header in "${CSV_HEADERS[@]}"; do
        VALUE=${current_array[$header]}
        # Handle commas within data fields for valid CSV format
        if [[ "$VALUE" == *","* ]]; then
            VALUE="\"$VALUE\""
        fi
        LINE="${LINE}${VALUE},"
    done
    # Print the line, removing the trailing comma
    echo "${LINE%,}"
done
