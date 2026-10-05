# Migrate to Docker

This guide describes how to move an existing **manual / server installation** of HumHub to this Docker image.

A migration is a regular [Docker restore](backup-restore.md#humhub-restore-guide-docker). The main difference is where
the data comes from: instead of a Docker backup archive, you take the database and files directly from your existing
installation. Follow the restore guide step by step and apply the differences described below.

> **Important:** Create a full [backup](https://docs.humhub.org/docs/admin/backup) of your existing installation before
> migrating, and keep the old installation untouched until the new one is verified.

## Before you start

- **Version:** Use an image version that is equal to or newer than the HumHub version of your existing installation.
  Database migrations are applied automatically on container start, a downgrade is not possible.
- **Docker stack:** Set up the stack as described in the [README](../README.md) and start it once, so the data volume
  is initialized.

## Migration data

Where the restore guide uses the content of a Docker backup archive, you take the data from your existing installation:

| Data | Source (existing installation) | Target (`§PATH_TO_HUMHUBDATA§`) |
|---|---|---|
| Database | Dump of your existing database | see [Database](#database) |
| Configuration | `protected/config/` | `config/` |
| Uploaded files | `uploads/` | `uploads/` |
| Custom themes | `themes/<YourTheme>/` | `themes/<YourTheme>/` |
| Custom modules | `protected/modules/<YourModule>/` | `modules-custom/<YourModule>/` |

`§PATH_TO_HUMHUBDATA§` is the path to the data volume defined in the `humhub` service within your `docker-compose.yml`.

### Database

Create a dump of your existing database, see the [HumHub Backup Documentation](https://docs.humhub.org/docs/admin/backup).

Import it as described in [Restore the Database](backup-restore.md#restore-the-database), depending on where the
database of your new Docker stack runs:

- **Database as Docker Compose service:** see
  [Database as Docker Compose Service](backup-restore.md#database-as-docker-compose-service-eg-mariadb-or-db).
- **External database server:** see [External Database Server](backup-restore.md#external-database-server).
  Always create a new, empty database for the Docker stack, also when you keep using the database server of your
  existing installation, and point the `HUMHUB_CONFIG__COMPONENTS__DB__*` variables of the `humhub` service to it.
  **Do not use the database of your existing installation directly: it is migrated to the image version on container
  start and can become unusable for your existing installation.**
  Make sure the database server is reachable from the container: `localhost` refers to the container itself, and the
  database user must be allowed to connect from the Docker network.

The restore guide expects a gzip compressed dump (`humhub_db_§TIMESTAMP§.sql.gz`) and reads it with `zcat`. For an
uncompressed dump (e.g. `export.sql`), use `cat export.sql` instead. Dumps compressed with other tools need the
matching command, e.g. `bzcat` or `xzcat`.

### Configuration

Copy the files from `protected/config/` (e.g. `common.php`, `web.php`, `console.php`, `dynamic.php`) into
`§PATH_TO_HUMHUBDATA§/config/`.

- The `HUMHUB_CONFIG__...` environment variables are applied after the configuration files, so the database settings
  of your existing installation (usually in `dynamic.php`) are superseded by those of your Docker stack.
- Review your custom configuration and remove settings the image already takes care of, e.g. pretty URLs or paths
  that pointed to your old installation.

### Files, themes and modules

Copy uploads, custom themes and custom modules as listed in the table above. This replaces extracting the storage
backup archive in [Restore the Storage Backup](backup-restore.md#restore-the-storage-backup).

- **Marketplace modules** do not need to be copied. Modules that are enabled in the database but missing on disk are
  installed automatically in their latest compatible version on container start.
- **The default `HumHub` theme** does not need to be copied, it is provided by the image.
- **Ownership and permissions** of the data volume are adjusted automatically on container start.

## Finish

Start the stack and verify the installation as described in the [Final Step](backup-restore.md#final-step) of the
restore guide.
