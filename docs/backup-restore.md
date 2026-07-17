# HumHub Backup Guide (Docker)

## Introduction
This document explains how to use the backup functionality included in our HumHub Docker image. For the official and most up-to-date documentation, please refer to the [HumHub Backup Documentation](https://docs.humhub.org/docs/admin/backup).

## Using the Docker Backup Service
Our Docker image includes a built-in backup functionality. It is recommended to integrate it as a separate service in your `compose.yml` file.

### Example `compose.yml` service
```yaml
  backup:
    extends:
      service: humhub
    profiles: ["manual"]
    restart: "no"
    command: /app/bin/humhub-backup.sh
    user: root
    volumes:
      - ./humhub-backup:/backup
    environment:
      - HUMHUB_DOCKER__BACKUP_MERGE_ARCHIVES=true
```

> **Important:** The `backup` service uses `extends` to inherit the image, environment (including database credentials, also from `env_file`) and volumes from your main `humhub` service, so they always stay in sync. You only add the backup-specific volume and settings, which are merged on top of the inherited ones.

### Notes

- You must define a separate volume for backups. We strongly recommend not placing the backup volume inside the data volume. Ideally, use a dedicated partition or even a remote storage such as Samba or NFS.
- The backup process generates a tar archive with the following format: `humhub_backup_§TIMESTAMP§.tar`
- This archive contains two files:
  - Database backup (gzipped SQL dump): `humhub_db_§TIMESTAMP§.sql.gz`
  - Storage backup (gzipped tar archive): `humhub_storage_backup_§TIMESTAMP§.tar.gz`
  - Where `§TIMESTAMP§` corresponds to the output of the `date` command with the format `'%Y%m%d%H%M%S'`.
- You can reduce temporary storage usage of the backup volume. Set the optional `HUMHUB_DOCKER__BACKUP_MERGE_ARCHIVES` environment variable to `false`.

## Running the Backup from the Host

You can execute the backup manually or schedule it via Cron.

### Manual execution

Run the following command from the host:

```bash
docker compose run --rm backup
```

- The container will automatically exit after the backup is complete.
- The exit code will be 0 on success or a non-zero value if an error occurred.

### Automatic execution via Cron

> **Important:** The administrator is responsible for **archiving, rotating, and cleaning up old backups.** The backup process itself does not manage retention.

To run the backup daily at 4:00 AM, add a cron job like this:

```cron
0 4 * * * cd /path/to/your/docker-compose && docker compose run --rm backup >> /var/log/humhub_backup.log 2>&1
```

- Replace `/path/to/your/docker-compose` with the directory containing your `compose.yml`. 
- Output and errors are redirected to `/var/log/humhub_backup.log`.
- The container will automatically terminate after each run and return the appropriate exit code (0 for success, non-zero for failure), which can be used for monitoring or alerting.

# HumHub Restore Guide (Docker)

## Introduction
This document describes how to restore a HumHub installation using Docker. For the official and most up-to-date documentation, please refer to the [HumHub Backup Documentation](https://docs.humhub.org/docs/admin/backup).

The backup to be restored must have been created using the procedure described above.  
It is expected to contain:

- A database dump:  
  `humhub_db_§TIMESTAMP§.sql.gz`
- A storage backup archive:  
  `humhub_storage_backup_§TIMESTAMP§.tar.gz`

Where `§TIMESTAMP§` corresponds to the format `'%Y%m%d%H%M%S'`.

---

# Restore Procedure

## Perform a Fresh Docker Installation

> **Important:** All following steps assume you are working on a **fresh Docker-based HumHub installation**.  
> Applying these steps on an existing installation may lead to **data loss**.

It is strongly recommended to start with a fresh Docker-based HumHub installation. This ensures that all required directories, volumes, and permissions are properly initialized.

If your original installation used `.env` files, make sure to recreate and configure them accordingly before proceeding. The new installation must use the same relevant environment configuration (database credentials, app settings, etc.) as the original instance.

After the initial setup is complete, proceed with stopping the environment.

---

## Stop the Complete Docker Environment

Shut down all running services:

```bash
docker compose down
```

## Restore the Database

Choose the appropriate method depending on whether your database is running as part of the Docker Compose stack or on an external server.

### Database as Docker Compose Service (e.g. `mariadb` or `db`)

If your database is defined as a service inside `docker-compose.yml`:

#### Step 1: Ensure everything is stopped and old database data is removed

```bash
docker compose down
sudo rm -Rf mysql-data/
```

> Adjust `mysql-data/` to match your actual database volume directory.

#### Step 2: Start only the database service

```bash
docker compose up db
```

Wait until the database is fully initialized and ready to accept connections.

#### Step 3: Import the database dump

The environment variables used for the database connection **must be available inside the Docker container**. In most setups, they are defined in `docker-compose.yml` (or `.env`) for the database service. You must use the same variable values here as defined in your Compose configuration.
```bash
zcat migration-data/humhub_db_§TIMESTAMP§.sql.gz | docker compose exec -T db sh -c 'mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'
```

Important:

- `MARIADB_USER`, `MARIADB_PASSWORD`, and `MARIADB_DATABASE` must be defined for the `db` service in `docker-compose.yml`.
- If your service uses different variable names, replace them accordingly.
- The file path `migration-data/` must match the location of your extracted backup.

### External Database Server

If your database runs outside Docker (external MariaDB/MySQL server), follow your database server documentation.

A typical restore command might look like:

```bash
zcat migration-data/humhub_db_§TIMESTAMP§.sql.gz | mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"
```

Ensure:

- Credentials are correct.
- The target database already exists.
- The database user has sufficient privileges.

## Restore the Storage Backup

Extract the storage archive to a temporary location:

```bash
tar -xzf humhub_storage_backup_§TIMESTAMP§.tar.gz
```

Modules are included in the backup for completeness, but they do **not** need to be copied manually. They will be reinstalled automatically during the next `docker compose up`.

Copy the required directories into the HumHub data volume:

```bash
cp -av data/config/ §PATH_TO_HUMHUBDATA§
cp -av data/uploads/ §PATH_TO_HUMHUBDATA§
```

`§PATH_TO_HUMHUBDATA§` is the path to the data volume defined in the `humhub` service within your `docker-compose.yml`.

Make sure:

- Files are copied into the correct mounted data directory.
- Ownership and permissions match the container requirements.

## Final Step

Start the complete Docker environment:

```bash
docker compose up -d
```

Verify:

- HumHub starts correctly
- Users can log in
- Uploaded files are accessible
- Configuration has been restored properly
- Your restoration should now be complete.