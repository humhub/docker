#!/bin/bash

#---------------------------------------------
#
# This script starts the Queue Listener.
# Before that, it checks whether the database connection and the HumHub setup have been completed.
#
#---------------------------------------------


sleep 5

# Wait until the database is reachable and fully migrated (read-only check)
/app/bin/humhub-wait-ready.sh

/app/yii queue/listen --verbose=1 --color=0
