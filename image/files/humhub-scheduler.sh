#!/bin/bash

# Prefix each output line with the supervisor process name, keeping stdout/stderr separate.
PREFIX="[${SUPERVISOR_PROCESS_NAME:-humhub-scheduler}]"
exec > >(while IFS= read -r line; do printf '%s %s\n' "$PREFIX" "$line"; done) \
     2> >(while IFS= read -r line; do printf '%s %s\n' "$PREFIX" "$line"; done >&2)

sleep 5

echo "Checking HumHub readiness (database, installation, migrations)..."
# Serialize the readiness probe (shared lock) so concurrent cache flushes can't race; scheduler is head, no jitter.
flock /tmp/humhub-wait-ready.lock /app/bin/humhub-wait-ready.sh

while true; do

    /app/yii cron/run
    sleep 60

done
