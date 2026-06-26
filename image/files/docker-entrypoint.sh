#!/bin/bash

#----------------------------------------------------------------------
# SPLASH SCREEN
#----------------------------------------------------------------------

echo
echo '        ,---__                                                         '
echo '       /      ---__                                                    '
echo '     /             --.      _    _                                     '
echo '   /                 |     | |  | |                 |    |       |     '
echo ' /              ,-,__|  ,. | |__| |_   _ _ __ ___   |    |       |     '
echo '|              (   __. (  =   __  | | | | `_ ` _ \  |----| .   . |---. '
echo ' \              `-´  |  `´ | |  | | |_| | | | | | | |    | |   | |   | '
echo '   \                 |     |_|  |_|\__,_|_| |_| |_| |    | `___| `___´ '
echo '     \           __--´                                                 '
echo '       \    __---                                                      '
echo '        `---                                                           '
echo
echo

#----------------------------------------------------------------------
# DETERMINE SINGLE OR MULTI SERVICE SETUP
#----------------------------------------------------------------------

#--- Set autostart true per defaults for all programs in supervisord
export HUMHUB_DOCKER__AUTOSTART_FRANKENPHP=${HUMHUB_DOCKER__AUTOSTART_FRANKENPHP:-"true"}
export HUMHUB_DOCKER__AUTOSTART_SCHEDULER=${HUMHUB_DOCKER__AUTOSTART_SCHEDULER:-"true"}
export HUMHUB_DOCKER__AUTOSTART_WORKER=${HUMHUB_DOCKER__AUTOSTART_WORKER:-"true"}
export HUMHUB_DOCKER__NUMPROCS_WORKER=${HUMHUB_DOCKER__NUMPROCS_WORKER:-"2"}

#----------------------------------------------------------------------
# MOUNTED DATA FOLDER HANDLING
#----------------------------------------------------------------------

#--- Ensure mounted data folder structure
mkdir -p /data/{uploads,assets,logs,config,modules,modules-custom,themes,caddy}

#--- Copy defaults (if not exist) to mounted data folder
cp -rn /opt/humhub/protected/config/ /data/
cp -rn /opt/humhub/uploads/ /data/

# Since HumHub v1.19, the default theme is no longer located in the themes folder.
# The themes folder is now reserved for custom themes only.
# Remove the default theme if it still exists (e.g. after an upgrade from an older version).
rm -rf /data/themes/HumHub

#--- Check Permissions
chown -R www-data:www-data /app/runtime
chown -R www-data:www-data /data/*
find /app/runtime/ -type d -exec chmod u=rwx,go=rx {} + -o -type f -exec chmod u=rw,go=r {} +
find /data/ -type d -exec chmod u=rwx,go=rx {} + -o -type f -exec chmod u=rw,go=r {} +

#----------------------------------------------------------------------
# HUMHUB INIT
#----------------------------------------------------------------------

#--- Ensure migrations and module updates are only executed in frankenphp context
if [ "$HUMHUB_DOCKER__AUTOSTART_FRANKENPHP" = "true" ]; then
  su www-data -s /bin/bash -c '/app/bin/humhub-startup.sh'
fi

if [ -n "$HUMHUB_CONFIG__COMPONENTS__DB__DSN" ] && [ -n "$HUMHUB_CONFIG__COMPONENTS__DB__USERNAME" ]; then
  AUTO_SETUP=true
fi
export HUMHUB_CONFIG__MODULES__INSTALLER__ENABLE_AUTO_SETUP="$AUTO_SETUP"

#----------------------------------------------------------------------
# Caddy: Configuration
#----------------------------------------------------------------------
#export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<'EOF'
#    log {
#      output stderr
#      level DEBUG
#      format console
#    }
#EOF
#)"
export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<'EOF'
  # Forbidden Directories
  respond /uploads/file/* 403
EOF
)"

#----------------------------------------------------------------------
# Caddy: Enable SendFile
#----------------------------------------------------------------------
export HUMHUB_FIXED_SETTINGS__FILE__USE_X_SENDFILE=1
export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<'EOF'
    # Enable Sendfile
    intercept {
        @accel header X-Accel-Redirect *
        handle_response @accel {
            root /app/public/
            rewrite * {resp.header.X-Accel-Redirect}
            method * GET
            file_server
        }
    }

EOF
)"

#----------------------------------------------------------------------
# FrankenPHP: PHP Defaults
#----------------------------------------------------------------------
export FRANKENPHP_CONFIG+="$(cat <<'EOF'
       # Default PHP INI
       php_ini upload_max_filesize 1G
       php_ini post_max_size 1G
       php_ini max_input_time 600
       php_ini max_execution_time 600

EOF
)"

#----------------------------------------------------------------------
# Enable Mercure
#----------------------------------------------------------------------
if [ "${HUMHUB_DOCKER__MERCURE_ENABLE}" = "true" ]; then
  export MERCURE_SECRET_PUB="$(head -c 32 /dev/urandom | base64)"
  export MERCURE_SECRET_SUB="$(head -c 32 /dev/urandom | base64)"
  export HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__CLASS='humhub\modules\live\driver\MercurePushDriver'
  export HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__JWT_KEY_SUBSCRIBER="${MERCURE_SECRET_SUB}"
  export HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__JWT_KEY_PUBLISHER="${MERCURE_SECRET_PUB}"
  export HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__VERIFY_SSL="false"

  # The hub is embedded in this container, so the server must publish to it over
  # loopback while the browser keeps subscribing via the public SERVER_NAME address.
  # Derive the internal (publish) URL from SERVER_NAME, swapping the host for
  # localhost but preserving scheme and port. Honors an explicit override.
  if [ -z "${HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__INTERNAL_HUB_URL}" ]; then
    _mercure_addr="${SERVER_NAME%% *}"
    case "$_mercure_addr" in
      https://*) _mercure_scheme="https"; _mercure_hostport="${_mercure_addr#https://}" ;;
      http://*)  _mercure_scheme="http";  _mercure_hostport="${_mercure_addr#http://}" ;;
      *)         _mercure_scheme="https"; _mercure_hostport="$_mercure_addr" ;; # Caddy auto-HTTPS
    esac
    case "$_mercure_hostport" in
      *:*) _mercure_internal="${_mercure_scheme}://localhost:${_mercure_hostport##*:}" ;;
      *)   _mercure_internal="${_mercure_scheme}://localhost" ;;
    esac
    export HUMHUB_CONFIG__COMPONENTS__LIVE__DRIVER__INTERNAL_HUB_URL="${_mercure_internal}/.well-known/mercure"
  fi

  mkdir -p /data/caddy; chown www-data:www-data /data/caddy
  export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<'EOF'
      # Enable Mercure
      mercure {
            transport local
            publisher_jwt {env.MERCURE_SECRET_PUB} HS256
            subscriber_jwt {env.MERCURE_SECRET_SUB} HS256
            anonymous
      }
EOF
)"
fi


#----------------------------------------------------------------------
# STARTUP
#----------------------------------------------------------------------

if [ -z "$@" ]; then
  exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf --nodaemon
else
  exec PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin $@
fi