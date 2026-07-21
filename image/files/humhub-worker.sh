#!/bin/bash

#---------------------------------------------
#
# This script starts the Queue Listener.
# Before that, it checks whether the database connection and the HumHub setup have been completed.
#
#---------------------------------------------

# Prefix each output line with the supervisor process name, keeping stdout/stderr separate.
PREFIX="[${SUPERVISOR_PROCESS_NAME:-humhub-worker}]"
exec > >(while IFS= read -r line; do printf '%s %s\n' "$PREFIX" "$line"; done) \
     2> >(while IFS= read -r line; do printf '%s %s\n' "$PREFIX" "$line"; done >&2)

sleep 5

# Wait until the database is reachable and fully migrated (read-only check)
/app/bin/humhub-wait-ready.sh

/app/yii queue/listen --verbose=1 --color=0
