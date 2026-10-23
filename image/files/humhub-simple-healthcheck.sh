#!/bin/sh

# Probe the web server of this container.
#
# The URL follows the first address of SERVER_NAME, because that is what decides how Caddy listens:
#   unset, localhost                  -> https://localhost
#   https://example.com[:port]        -> https://example.com[:port]  (automatic HTTPS, the default)
#   http://example.com[:port]         -> http://example.com[:port]   (plain HTTP, e.g. TLS terminated by a reverse proxy)
#   :port, example.com:80             -> http://...                  (plain HTTP)
# The connection always goes to 127.0.0.1 (curl --connect-to), while the host name is kept for
# TLS SNI and the Host header, so Caddy matches the actual site instead of an unknown "localhost".
# HUMHUB_DOCKER__HEALTHCHECK_URL overrides the derived URL and is requested as is.
if [ -n "$HUMHUB_DOCKER__HEALTHCHECK_URL" ]; then
    URL="$HUMHUB_DOCKER__HEALTHCHECK_URL"
    set --
else
    # First address only, without scheme and path
    address="${SERVER_NAME:-localhost}"
    address="${address#"${address%%[! ]*}"}"
    address="${address%%[, ]*}"
    case "$address" in
        http://*)  scheme="http";  address="${address#http://}" ;;
        https://*) scheme="https"; address="${address#https://}" ;;
        *)         scheme="" ;;
    esac
    address="${address%%/*}"

    # Split host and port, IPv6 hosts are enclosed in brackets
    case "$address" in
        \[*\]:*) host="${address%]:*}]"; port="${address##*]:}" ;;
        \[*\])   host="$address";        port="" ;;
        *:*)     host="${address%:*}";   port="${address##*:}" ;;
        *)       host="$address";        port="" ;;
    esac

    # Without a scheme, Caddy serves plain HTTP for a missing host or port 80, HTTPS otherwise
    if [ -z "$scheme" ]; then
        if [ -z "$host" ] || [ "$port" = "80" ]; then
            scheme="http"
        else
            scheme="https"
        fi
    fi

    URL="${scheme}://${host:-localhost}${port:+:$port}"
    set -- --connect-to "::127.0.0.1:"
fi

# -k: ignore self-signed certificates
# -f: fail on HTTP errors (>= 400)
# -s: silent mode
# -g: no URL globbing, so IPv6 hosts in brackets work
# -o /dev/null: discard output
# --max-time 2: timeout after 2 seconds
exec curl -k -f -s -g -o /dev/null --max-time 2 "$@" "$URL"
