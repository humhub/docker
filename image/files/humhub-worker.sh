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

# Randomized delay so the workers don't grab the lock at once and the scheduler (no jitter) gets it first.
sleep $((6 + RANDOM % 8))

# Wait behind the shared lock (see humhub-scheduler.sh); own check kept for safety.
flock /tmp/humhub-wait-ready.lock /app/bin/humhub-wait-ready.sh

/app/yii queue/listen --verbose=1 --color=0
