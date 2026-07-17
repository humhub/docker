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

while true; do

    output=$(/app/yii queue/info 2>&1)

    if [[ "$output" != *'yii\\db\\Exception'* ]]; then
        echo "Database connection successful. Initiated..."
        break
    else
        echo "Database not configured and initialized. Waiting..."
        sleep 30
    fi
done

/app/yii queue/listen --verbose=1 --color=0
