# Migrate to Docker

This guide describes how to move an existing **manual / server installation** of HumHub to this Docker image.

> **Important:** Create a full [backup](https://docs.humhub.org/docs/admin/backup) of your existing installation before
> migrating, and keep the old installation untouched until the new one is verified.

## Quick Migration (Standard Installation)

These steps cover the most common case:

- Your existing HumHub installation is located in `/var/www/humhub` and uses a MariaDB/MySQL database.
- The new Docker stack is set up exactly as in the [Quick Start](../README.md#quick-start) of the README, in
  `/opt/humhub` with the `db` service.
- Only the default `HumHub` theme and modules from the marketplace are used.

If your setup differs, see [Details and Other Setups](#details-and-other-setups) below.

### 1. Check the version and stop the old installation

Look up the HumHub version of your existing installation under **Administration → Information**. The Docker image
must have the **same or a newer** version (a downgrade is not possible), so pick the image tag in your
`docker-compose.yml` accordingly.

Then stop the web server and cron jobs of the existing installation, so no data changes during the migration.

### 2. Create a database dump

Replace `<db_user>` and `<db_name>` with the values of your existing installation (see
`/var/www/humhub/protected/config/dynamic.php`):

```bash
mysqldump --single-transaction -u <db_user> -p <db_name> > /opt/humhub/humhub.sql
```

### 3. Set up the Docker stack

Create the `docker-compose.yml` as described in the [Quick Start](../README.md#quick-start), start it once so the data
directory is initialized, and stop it again. **Do not run the web installer.**

```bash
cd /opt/humhub
docker compose up -d
docker compose down
```

### 4. Import the database

```bash
cd /opt/humhub
docker compose up -d db
docker compose exec -T db sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS humhub CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"'
docker compose exec -T db sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" humhub' < humhub.sql
```

### 5. Copy configuration and uploaded files

```bash
cd /opt/humhub
sudo cp -a /var/www/humhub/protected/config/. humhub-data/config/
sudo cp -a /var/www/humhub/uploads/. humhub-data/uploads/
```

### 6. Start HumHub

```bash
docker compose up -d
docker compose logs -f humhub
```

On startup, the database is migrated to the image version and the enabled marketplace modules are installed
automatically. Then verify that:

- HumHub starts correctly and users can log in
- Uploaded files (e.g. profile images, attachments) are accessible
- All modules are enabled and working

Once everything works, point your domain to the new server (if it changed) and remove `/opt/humhub/humhub.sql`.

## Details and Other Setups

### What is migrated

| Data | Source (existing installation) | Target (`§PATH_TO_HUMHUBDATA§`) |
|---|---|---|
| Database | Dump of your existing database | see [Database](#database) |
| Configuration | `protected/config/` | `config/` |
| Uploaded files | `uploads/` | `uploads/` |
| Custom themes | `themes/<YourTheme>/` | `themes/<YourTheme>/` |
| Custom modules | `protected/modules/<YourModule>/` | `modules-custom/<YourModule>/` |

`§PATH_TO_HUMHUBDATA§` is the path to the data volume defined in the `humhub` service within your `docker-compose.yml`
(`./humhub-data` in the Quick Start).

### Database

The dump can be created as described in the [HumHub Backup Documentation](https://docs.humhub.org/docs/admin/backup).

- **Compressed dumps:** Use `zcat`, `bzcat` or `xzcat` and pipe the output into the import command instead of
  redirecting the file with `<`.
- **Different database service:** If your `db` service uses other credentials or creates the database itself (e.g.
  via `MARIADB_DATABASE`), adjust the import command, see
  [Database as Docker Compose Service](backup-restore.md#database-as-docker-compose-service-eg-mariadb-or-db).
- **External database server:** see [External Database Server](backup-restore.md#external-database-server).
  Always create a new, empty database for the Docker stack, also when you keep using the database server of your
  existing installation, and point the `HUMHUB_CONFIG__COMPONENTS__DB__*` variables of the `humhub` service to it.
  **Do not use the database of your existing installation directly: it is migrated to the image version on container
  start and can become unusable for your existing installation.**
  Make sure the database server is reachable from the container: `localhost` refers to the container itself, and the
  database user must be allowed to connect from the Docker network.

### Configuration

The files from `protected/config/` (e.g. `common.php`, `web.php`, `console.php`, `dynamic.php`) are copied into
`§PATH_TO_HUMHUBDATA§/config/`.

- The `HUMHUB_CONFIG__...` environment variables are applied after the configuration files, so the database settings
  of your existing installation (usually in `dynamic.php`) are superseded by those of your Docker stack.
- Review your custom configuration and remove settings the image already takes care of, e.g. pretty URLs or paths
  that pointed to your old installation.

### Themes and modules

- **Marketplace modules** do not need to be copied. Modules that are enabled in the database but missing on disk are
  installed automatically in their latest compatible version on container start.
- **Custom modules and themes** (not from the marketplace) must be copied as listed in the table above, see
  [Custom Themes and Modules](custom-themes-modules.md).
- **The default `HumHub` theme** does not need to be copied, it is provided by the image.
- **Ownership and permissions** of the data volume are adjusted automatically on container start.

### Moving to another server

If the Docker stack runs on a different server, create the dump on the old server and transfer it together with
`protected/config/`, `uploads/` and any custom themes or modules (e.g. with `rsync` or `scp`). Then continue with the
steps above, using the transferred paths instead of `/var/www/humhub`.
