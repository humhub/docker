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

#--- Logging defaults (see docs/logging.md)
export HUMHUB_DOCKER__ACCESS_LOG=${HUMHUB_DOCKER__ACCESS_LOG:-"false"}
export HUMHUB_DOCKER__ACCESS_LOG_FORMAT=${HUMHUB_DOCKER__ACCESS_LOG_FORMAT:-"json"}
export HUMHUB_DOCKER__ACCESS_LOG_OUTPUT=${HUMHUB_DOCKER__ACCESS_LOG_OUTPUT:-"stdout"}
export HUMHUB_DOCKER__ACCESS_LOG_FILE=${HUMHUB_DOCKER__ACCESS_LOG_FILE:-"/data/logs/access.log"}
export HUMHUB_DOCKER__ACCESS_LOG_ROLL_SIZE=${HUMHUB_DOCKER__ACCESS_LOG_ROLL_SIZE:-"10MiB"}
export HUMHUB_DOCKER__ACCESS_LOG_ROLL_KEEP=${HUMHUB_DOCKER__ACCESS_LOG_ROLL_KEEP:-"5"}
export HUMHUB_DOCKER__SERVER_LOG=${HUMHUB_DOCKER__SERVER_LOG:-"true"}
export HUMHUB_DOCKER__SERVER_LOG_LEVEL=${HUMHUB_DOCKER__SERVER_LOG_LEVEL:-"INFO"}
export HUMHUB_DOCKER__SERVER_LOG_FORMAT=${HUMHUB_DOCKER__SERVER_LOG_FORMAT:-"json"}
export HUMHUB_DOCKER__SERVER_LOG_OUTPUT=${HUMHUB_DOCKER__SERVER_LOG_OUTPUT:-"stderr"}
export HUMHUB_DOCKER__SERVER_LOG_FILE=${HUMHUB_DOCKER__SERVER_LOG_FILE:-"/data/logs/server.log"}
export HUMHUB_DOCKER__APP_LOG_STDOUT=${HUMHUB_DOCKER__APP_LOG_STDOUT:-"false"}

#----------------------------------------------------------------------
# MOUNTED DATA FOLDER HANDLING
#----------------------------------------------------------------------

#--- Ensure mounted data folder structure
mkdir -p /data/{uploads,assets,logs,config,modules,modules-custom,themes,caddy}

#--- Copy defaults (if not exist) to mounted data folder
cp -rn /opt/humhub/protected/config/ /data/
cp -rn /opt/humhub/uploads/ /data/
rm -rf /data/themes/HumHub && cp -rf /opt/humhub/themes/HumHub /data/themes/HumHub

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
export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<'EOF'
  # Forbidden Directories
  respond /uploads/file/* 403
EOF
)"

#----------------------------------------------------------------------
# Logging: server runtime/error log (Caddy default logger)
# See docs/logging.md
#----------------------------------------------------------------------
if [ "$HUMHUB_DOCKER__SERVER_LOG" != "true" ]; then
  _server_log_output="output discard"
elif [ "$HUMHUB_DOCKER__SERVER_LOG_OUTPUT" = "file" ]; then
  _server_log_output="output file ${HUMHUB_DOCKER__SERVER_LOG_FILE}"
else
  _server_log_output="output ${HUMHUB_DOCKER__SERVER_LOG_OUTPUT}"
fi
export CADDY_GLOBAL_OPTIONS+="$(cat <<EOF

  log {
    ${_server_log_output}
    level ${HUMHUB_DOCKER__SERVER_LOG_LEVEL}
    format ${HUMHUB_DOCKER__SERVER_LOG_FORMAT}
  }
EOF
)"

#----------------------------------------------------------------------
# Logging: HTTP access log (site-scoped, opt-out via ACCESS_LOG=false)
#----------------------------------------------------------------------
if [ "$HUMHUB_DOCKER__ACCESS_LOG" = "true" ]; then
  if [ "$HUMHUB_DOCKER__ACCESS_LOG_OUTPUT" = "file" ]; then
    _access_log_output="output file ${HUMHUB_DOCKER__ACCESS_LOG_FILE} {
      roll_size ${HUMHUB_DOCKER__ACCESS_LOG_ROLL_SIZE}
      roll_keep ${HUMHUB_DOCKER__ACCESS_LOG_ROLL_KEEP}
    }"
  else
    _access_log_output="output ${HUMHUB_DOCKER__ACCESS_LOG_OUTPUT}"
  fi
  export CADDY_SERVER_EXTRA_DIRECTIVES+="$(cat <<EOF

  # HTTP access log
  log {
    ${_access_log_output}
    format filter {
      wrap ${HUMHUB_DOCKER__ACCESS_LOG_FORMAT}
      # Redact the Mercure authorization query parameter
      request>uri query {
        replace authorization REDACTED
      }
    }
  }
EOF
)"
fi

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
            header -X-Accel-Redirect
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
       php_ini log_errors On
       php_ini display_errors Off

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