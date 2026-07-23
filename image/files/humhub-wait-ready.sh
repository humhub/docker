#!/bin/bash

#----------------------------------------------------------------------
# Block until HumHub is installed AND the database schema is fully migrated.
#
# This prevents background services (scheduler, worker) from running
# against a not-yet-installed or half-migrated schema during first-boot
# auto-setup or an upgrade, which otherwise fails with errors like
# "Unknown column ... in 'WHERE'".
#
# IMPORTANT: this only VERIFIES state, it never changes it:
#   - "settings/list-module admin" reads settings (read-only).
#   - "migrate/new" only lists pending migrations, it never applies them.
# It is intentionally gated on "installed" first, so migrate/new is only
# run once the installer has created the schema (and the migration table),
# avoiding any write side effect on a fresh, empty database.
#----------------------------------------------------------------------

echo "Checking HumHub readiness (database, installation, migrations)..."

#--- 1) Wait until HumHub is installed
while true; do
    if [[ "$(/app/yii settings/list-module admin 2>&1)" == *"installationId"* ]]; then
        break
    fi
    echo "HumHub not installed yet. Waiting..."
    sleep 15
done

#--- 2) Wait until all migrations (core + modules) have been applied
while true; do
    if [[ "$(/app/yii migrate/new 2>&1)" == *"No new migrations found"* ]]; then
        echo "Database installed and fully migrated. Initiated..."
        break
    fi
    echo "Database not fully migrated yet. Waiting..."
    sleep 15
done
