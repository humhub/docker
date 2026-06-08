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

fi