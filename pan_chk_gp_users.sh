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

## Requirements
# Installed packages: openssl, pan-python, xmlstarlet

## Fixed variables
# Reuse pan_instcert API key
API_KEY="/etc/ipa/.panrc"
# XSLT filter path
XSL_PATH="/etc/panos"
XSL_USERS="process-users.xsl"
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
    if ! ( : >> "$LOG" ) &>/dev/null; then
        echo "ERROR: Can't write to log file: $LOG. Sudo or root expected."
        exit 1
    else
        printf "[$(date --rfc-3339=seconds)]: $*" >> "$LOG"
    fi
}
# On error log a last line
trap 'wlog "ERROR - Check GP users failed.\n"' TERM HUP

## Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-hv] [OPTIONS] FQDN/PATH
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
    -x path           Path to XSLT filters.        (default: /etc/panos/)
    -g gateway        GlobalProtect gateway.       (default: all)
    -d domain         GlobalProtect domain.        (default: all)
    -c                Check client certs           (default: no)

    -h                Display this help and exit.
    -v                Verbose mode.
EOF
}

## Read/interpret optional arguments
while getopts k:x:g:d:cvh opt; do
    case $opt in
        k)  API_KEY=$OPTARG
            ;;
        x)  XSL_PATH=$OPTARG
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

# Start logging
wlog "START of pan_chk_gp_users.\n"

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
    (( $VERBOSE > 0 )) && wlog "API key read from file.\n"
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
    if [[ "$API_KEY" == "/etc/ipa/.panrc" ]] && TEST=$(read_cfg "api_key" "$CFG_FILE"); then
        API_KEY="$TEST"
        (( $VERBOSE > 0 )) && wlog "API key found in: $CFG_FILE\n"
    fi
    # Try to read XSLT filter path from config file if not parsed with -x
    if [[ "$XSL_PATH" == "/etc/panos" ]] && TEST=$(read_cfg "xsl_filter_path" "$CFG_FILE"); then
        XSL_PATH="$TEST"
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
    if [[ "$CHK_CERTS" != "true" ]] && CHK_CERTS=$(read_cfg "chk_client_certs" "$CFG_FILE"); then
        :
    else
        CHK_CERTS=false
    fi
    if [[ "$CHK_CERTS" == "true" ]]; then
        (( $VERBOSE > 0 )) && wlog "Checking client certificates.\n"
            # Try to read a certificate name filter from the config file
            if TEST_CRT_FLT=$(read_cfg "cert_filter" "$CFG_FILE"); then
                CRT_FLT="$TEST_CRT_FLT"
            fi
            (( $VERBOSE > 0 )) && wlog "Filtering certificates by \"$CRT_FLT\"\n"
    else
        (( $VERBOSE > 0 )) && wlog "Not checking client certificates.\n"
    fi
fi

# Throw an error if an API_KEY is not yet found
if [[ "$API_KEY" == "/etc/ipa/.panrc" ]]; then
    (( $VERBOSE > 0 )) && wlog "ERROR: No API KEY parsed and/or found.\n"
    show_help >&2
    exit 1
fi

# Sanity check, at least one host must be known
if [ -z "$PAN_MGMT" ]; then
    (( $VERBOSE > 0 )) && wlog "ERROR: No host found, terminating.\n"
    exit 1
fi
if [[ "$API_KEY" == "/etc/ipa/.panrc" ]]; then
    (( $VERBOSE > 0 )) && wlog "ERROR: No API key found. Parse option '-k', check the config file or $API_KEY\n"
    exit 5
fi

# Function to run the panxapi command and get the raw XML
# Use 'grep -v' to filter out the status lines panxapi.py prints to stdout
get_api_xml() {
    local _cmd_xml="$1"
    local xml
    # Check if this is a config query (starts with '/') or op query (starts with '<')
    if [[ "$_cmd_xml" == "/"* ]]; then
        xml=$(panxapi.py -h "$PAN_MGMT" -K "$API_KEY" -gx "$_cmd_xml" 2>/dev/null)
    else
        xml=$(panxapi.py -h "$PAN_MGMT" -K "$API_KEY" -xo "$_cmd_xml" 2>/dev/null)
    fi
    if [[ -z "$xml" ]] || grep -q "<error>" <<<"$xml"; then
        (( $VERBOSE > 0 )) && wlog "ERROR: API query failed to retrieve XML data. Check credentials and privileges.\n"
        return 1
    fi
    # Remove noise
    echo "$xml"
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
(( $VERBOSE > 0 )) && wlog "Fetching Current User data.\n"
if ! curr_xml_data=$(get_api_xml "<show><global-protect-gateway><current-user>$xml_sub</current-user></global-protect-gateway></show>"); then
    exit 1
fi
(( $VERBOSE > 0 )) && wlog "Fetching Previous User data.\n"
if ! prev_xml_data=$(get_api_xml "<show><global-protect-gateway><previous-user>$xml_sub</previous-user></global-protect-gateway></show>"); then
    exit 1
fi

# Conditionally, fetch client certificate data
if [[ "$CHK_CERTS" == "true" ]]; then
    (( $VERBOSE > 0 )) && wlog "Fetching client certificate data.\n"
    if ! cert_xml_data=$(get_api_xml "/config/shared/certificate/entry[contains(@name, '$CRT_FLT' )]"); then
        (( $VERBOSE > 0 )) && wlog "ERROR: Failed to retrieve client certificate data. Check API KEY validity and privileges.\n" >&2
        # Don't exit, but report on the data that was successfully obtained
    fi
fi

# Combine the GlobalProtect XML output for current and previous users
TMP_XML=$(mktemp)
{
    printf "<records>\n";
    echo "$curr_xml_data" | xmlstarlet ed -s "/response/result/entry" -t elem -n active -v "yes" | xmlstarlet sel -t -c "/response/result/entry";
    echo "$prev_xml_data" | xmlstarlet ed -s "/response/result/entry" -t elem -n active -v "no" | xmlstarlet sel -t -c "/response/result/entry";
    if [ -n "$cert_xml_data" ]; then
        echo "$cert_xml_data" | xmlstarlet sel -t \
          -m "/response/result/entry[substring(@name, string-length(@name)-3) = '$CRT_FLT']" \
          -o "<entry>" -n \
          -o "  <username>" -v "common-name" -o "</username>" -n \
          -o "  <cert-name>" -v "@name" -o "</cert-name>" -n \
          -o "  <cert-expiry>" -v "not-valid-after" -o "</cert-expiry>" -n \
          -o "</entry>" -n
    fi
    printf "\n</records>\n";
} | xmlstarlet tr "$XSL_PATH/$XSL_USERS" > "$TMP_XML"

cat "$TMP_XML"

# Clean up temp files
rm "$TMP_XML" &>/dev/null
