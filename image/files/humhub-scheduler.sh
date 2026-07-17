#!/bin/bash

sleep 5

# Wait until the database is reachable and fully migrated (read-only check)
/app/bin/humhub-wait-ready.sh

while true; do

    /app/yii cron/run
    sleep 60

done
