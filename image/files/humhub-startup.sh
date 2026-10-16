#!/bin/bash

# Check if the current user is 'www-data'
if [ "$(whoami)" != "www-data" ]; then
  echo "Error: This script must be run as the 'www-data' user." >&2
  exit 1
fi

# Check if HumHub is installed
adminSettings=$(/app/yii settings/list-module admin 2>&1)
if [[ $adminSettings == *"installationId"* ]]; then

   /app/yii cache/flush-all
   /app/yii migrate/up --includeModuleMigrations=0 --interactive=0
   /app/yii module/update-all
   # Module migrations last, once the modules are up to date. A module that update-all did not touch
   # (a custom module, a module already at its latest version, a database restored from a backup) may
   # still have pending migrations, and humhub-wait-ready.sh keeps the scheduler and the workers
   # waiting until none is left.
   /app/yii migrate/up --includeModuleMigrations=1 --interactive=0

fi