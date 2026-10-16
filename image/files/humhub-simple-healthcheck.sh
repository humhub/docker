#!/bin/sh

# Probe the web server of this container.
#
# The URL follows SERVER_NAME, because that is what decides how Caddy listens:
#   https://example.com         -> https://localhost        (automatic HTTPS, the default)
#   http://example.com[:port]   -> http://localhost[:port]  (plain HTTP, e.g. TLS terminated by a reverse proxy)
#   :port                       -> http://localhost:port    (plain HTTP on that port)
# HUMHUB_DOCKER__HEALTHCHECK_URL overrides the derived URL.
if [ -n "$HUMHUB_DOCKER__HEALTHCHECK_URL" ]; then
    URL="$HUMHUB_DOCKER__HEALTHCHECK_URL"
else
    case "$SERVER_NAME" in
        http://*)  scheme="http";  hostport="${SERVER_NAME#http://}" ;;
        https://*) scheme="https"; hostport="${SERVER_NAME#https://}" ;;
        :*)        scheme="http";  hostport="localhost${SERVER_NAME}" ;;
        *)         scheme="https"; hostport="$SERVER_NAME" ;;
    esac
    # First address only, without any path
    hostport="${hostport%%[/, ]*}"
    case "$hostport" in
        *:*) port=":${hostport##*:}" ;;
        *)   port="" ;;
    esac
    URL="${scheme}://localhost${port}"
fi

# -k: ignore self-signed certificates
# -f: fail on HTTP errors (>= 400)
# -s: silent mode
# -o /dev/null: discard output
# --max-time 2: timeout after 2 seconds
curl -k -f -s -o /dev/null --max-time 2 "$URL"

exit $?
