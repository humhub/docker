# PHP Configuration

The image ships default PHP settings suitable for HumHub.
They can be changed with a custom ini file or, for the web server only, with the `FRANKENPHP_CONFIG` environment variable.

---

## Default Settings

The defaults are built into the image as `/usr/local/etc/php/conf.d/50-humhub.ini`:

| Setting               | Value |
|-----------------------|-------|
| `upload_max_filesize` | `1G`  |
| `post_max_size`       | `1G`  |
| `max_input_time`      | `600` |
| `max_execution_time`  | `600` |
| `log_errors`          | `On`  |
| `display_errors`      | `Off` |

All other settings use the PHP defaults.

---

## Custom ini File (recommended)

The recommended way to define your own PHP settings is a custom ini file mounted into the container.

Create a `php.ini` file in the same directory as your `docker-compose.yml`,
containing only the settings you want to change.
The values below are examples only; adjust them to your needs:

```ini
upload_max_filesize = 2G
post_max_size = 2G
memory_limit = 512M
```

Then mount it into the `humhub` service in your `docker-compose.yml`:

```yaml
services:
  humhub:
    volumes:
      - ./php.ini:/usr/local/etc/php/conf.d/99-custom.ini:ro
      # ... remaining volumes unchanged
```

Finally, recreate the container:

```bash
docker compose up -d
```

PHP loads the files in `conf.d` in alphabetical order, so `99-custom.ini` overrides `50-humhub.ini`.
The settings apply to all processes: web server, queue workers, scheduler and console commands.

---

## FRANKENPHP_CONFIG (web server only)

Settings can also be passed to the FrankenPHP web server as `php_ini` directives,
one per line:

```yaml
services:
  humhub:
    environment:
      FRANKENPHP_CONFIG: |
        php_ini upload_max_filesize 2G
        php_ini post_max_size 2G
```

These directives override any ini file, but only for web requests.
Queue workers, scheduler and console commands do not see them,
so use the custom ini file for settings such as `memory_limit` that matter for background jobs.

---

## Notes

- The format of both is not validated by the image.
  An invalid `FRANKENPHP_CONFIG` prevents the web server from starting.
  An invalid line in the ini file only logs a PHP warning, and all following lines of that file are ignored.
- HumHub has its own maximum upload file size under **Administration > Settings > Advanced > Files**.
  The effective limit is the lowest of this value, `upload_max_filesize` and `post_max_size`.
