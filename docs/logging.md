# Logging

This image separates logs into three concerns:

1. **Operational logs** produced by the web server and PHP runtime (access and error logs).
2. **Application logs** produced by HumHub itself (Yii), available as a file and in the admin UI.
3. **Peripheral logs** from workers, cron, migrations and backups.

By default the operational logs are written to the container's `stdout`/`stderr`
so they can be picked up by `docker logs` or any log driver without extra setup.
Following the common container convention, the two streams are kept separate:

- **`stdout`** carries the **HTTP access log** (disabled by default, see below).
- **`stderr`** carries **server diagnostics/errors** and **PHP errors**.

> [!NOTE]
> The HTTP access log is **off by default** because it is very verbose; enable it
> with `HUMHUB_DOCKER__ACCESS_LOG=true`. Each stream can instead be switched to a
> rotated file under the `/data` volume.

> [!IMPORTANT]
> Docker does **not** rotate or truncate container (`stdout`/`stderr`) logs by
> default: the default `json-file` driver grows unbounded until it fills the disk.
> Bounding and rotating them is the operator's responsibility. See
> [Persistence and rotation](#persistence-and-rotation) below.

---

## Log inventory

| Source | Content | Default destination | Default format | Rotation |
|---|---|---|---|---|
| HTTP access log | One entry per request | `stdout` (disabled by default) | JSON | Docker log driver (stdout) or Caddy roll (file) |
| Server runtime/error log | Startup, TLS, routing, panics (the `error_log` analog) | `stderr` | JSON | Docker log driver (stderr) or Caddy roll (file) |
| PHP errors (web) | Fatals, warnings, notices from web requests | rides the server log (`logger=frankenphp`) | server log format | follows the server log |
| PHP errors (CLI) | Errors from worker / scheduler / `yii` | `stderr` | PHP text | Docker log driver |
| HumHub app log (`FileTarget`) | App `error` + `warning` | `/data/logs/app.log` (also mirrored to `stdout` by default) | Yii text | Yii built-in: 10 MB x 5 files |
| HumHub app log (`DbTarget`) | App `error` + `warning` | `log` DB table (admin UI) | DB rows | Daily cron prune, 7 day retention |
| Worker | Queue job output | `stdout`/`stderr` | text | Docker log driver |
| Scheduler | Cron run output | `stdout`/`stderr` | text | Docker log driver |
| Startup | Migrations, module updates | `stdout` | text | Docker log driver |

The container streams are surfaced through `docker logs <container>`. The HumHub app
log is additionally visible under **Administration -> Information -> Logging**.

---

## Where do I look?

| Problem | Look here |
|---|---|
| Which requests hit the server, status codes, timing | HTTP access log (`stdout`) |
| TLS, certificate, routing or startup failures | Server runtime/error log (`stderr`) |
| White screen / HTTP 500 | PHP errors (`stderr`) and HumHub app log |
| Application warnings and errors | `/data/logs/app.log` or the admin Logging page |
| Failed background jobs | Worker output |
| Missed cron tasks | Scheduler output |
| Failed migrations on start | Startup output |

---

## Configuration

All logging is controlled through environment variables. By default the access
log is off, and server diagnostics/errors go to `stderr` as JSON.

### HTTP access log

| Variable | Default | Values | Description |
|---|---|---|---|
| `HUMHUB_DOCKER__ACCESS_LOG` | `false` | `true`, `false` | Enable the HTTP access log |
| `HUMHUB_DOCKER__ACCESS_LOG_FORMAT` | `json` | `json`, `console` | `json` for aggregators, `console` for humans |
| `HUMHUB_DOCKER__ACCESS_LOG_OUTPUT` | `stdout` | `stdout`, `file` | Container stream or a file on `/data` |
| `HUMHUB_DOCKER__ACCESS_LOG_FILE` | `/data/logs/access.log` | path | File path when output is `file` |
| `HUMHUB_DOCKER__ACCESS_LOG_ROLL_SIZE` | `100MiB` | size | Rotate file after this size |
| `HUMHUB_DOCKER__ACCESS_LOG_ROLL_KEEP` | `5` | count | Number of rotated files to keep |

The Mercure `authorization` query parameter is always redacted in the access log
(the Mercure real-time hub passes its subscriber JWT this way when a browser
`EventSource` cannot send a header). The filter is a no-op when the parameter is
absent, so it is kept on regardless of whether Mercure is enabled.

### Server runtime/error log

| Variable | Default | Values | Description |
|---|---|---|---|
| `HUMHUB_DOCKER__SERVER_LOG` | `true` | `true`, `false` | Enable the server log (`false` discards it, not recommended) |
| `HUMHUB_DOCKER__SERVER_LOG_LEVEL` | `INFO` | `ERROR`, `WARN`, `INFO`, `DEBUG` | Verbosity of the web server log |
| `HUMHUB_DOCKER__SERVER_LOG_FORMAT` | `json` | `json`, `console` | Log encoder |
| `HUMHUB_DOCKER__SERVER_LOG_OUTPUT` | `stderr` | `stdout`, `stderr`, `file` | Destination |
| `HUMHUB_DOCKER__SERVER_LOG_FILE` | `/data/logs/server.log` | path | File path when output is `file` |

When `SERVER_LOG_OUTPUT=file`, the file is rotated by Caddy's built-in defaults
(100 MiB, 10 files, 90 days). These are not exposed as env vars (unlike the access
log's `*_ROLL_*`) because the server log is low-volume. On `stdout`/`stderr`,
rotation is the Docker log driver's responsibility, not Caddy's.

### Client IP behind a reverse proxy

The access log records `remote_ip` (the direct TCP peer) and `client_ip`. When the
container runs behind a reverse proxy or is reached through the Docker gateway, the
peer is the proxy/gateway (e.g. `172.18.0.1`) and the real visitor IP is only in
the `X-Forwarded-For` header. The image does **not** trust that header by default:
surfacing (and where required anonymizing) real client IPs is a data-privacy
decision left to the reverse-proxy operator.

To have Caddy derive the client IP from `X-Forwarded-For`, set the base image's
`CADDY_GLOBAL_OPTIONS` variable (mapping syntax keeps the multi-line value):

```yaml
services:
  humhub:
    environment:
      CADDY_GLOBAL_OPTIONS: |
        servers {
          trusted_proxies static private_ranges
          client_ip_headers X-Forwarded-For
        }
```

Replace `private_ranges` with your proxy's IP/CIDR to trust only that source. Note
that this makes real client IPs (IPv4/IPv6, personal data under GDPR) appear in the
access log; anonymize or drop them at your proxy, or via a Caddy log filter, per
your privacy requirements.

### HumHub application log

The file (`/data/logs/app.log`) and database targets are configured by HumHub core
and are always active. By default `app.log` is also mirrored onto the container
`stdout` (so it is visible via `docker logs` / any log driver); set the variable to
`false` if you only want the file:

| Variable | Default | Values | Description |
|---|---|---|---|
| `HUMHUB_DOCKER__APP_LOG_STDOUT` | `true` | `true`, `false` | Tail `app.log` to the container `stdout` |

### PHP errors

PHP error logging is always on (`log_errors On`) and `display_errors` is always
`Off`, so errors are never leaked to the browser; a dedicated developer image can
override this.

**Where they go depends on the SAPI:**

- **Web requests:** FrankenPHP funnels PHP errors into the server (default) logger
  under `logger=frankenphp`, so they follow the `SERVER_LOG_*` settings. With the
  default `SERVER_LOG_OUTPUT=stderr` they appear on the container `stderr` next to
  the server diagnostics; with `SERVER_LOG_OUTPUT=file` they are written into the
  server log **file** instead. Note that `SERVER_LOG=false` (`output discard`) also
  discards web PHP errors.
- **CLI (worker, scheduler, `yii`):** these run the plain `php` binary and write
  errors to their own process `stderr`, which always reaches the container
  `stderr` regardless of the `SERVER_LOG` settings.

### Enabling the access log

The access log is off by default (one entry per request is very verbose). Turn it
on when you need request-level visibility:

```
HUMHUB_DOCKER__ACCESS_LOG=true
```

---

## Log paths: in-container vs. host

Log **files** only reach the host when they are written under a mounted volume.
With the usual `- ./humhub-data:/data` mount:

| In-container path | On the host | Persisted? |
|---|---|---|
| `/data/logs/access.log` | `./humhub-data/logs/access.log` | Yes (volume) |
| `/data/logs/server.log` | `./humhub-data/logs/server.log` | Yes (volume) |
| `/data/logs/app.log` | `./humhub-data/logs/app.log` | Yes (volume) |
| any path outside `/data` | not visible | No (container layer, lost on recreate) |

Only point `*_FILE` variables at paths under `/data` (or another mounted volume).
A path in the container's own filesystem works but the file is ephemeral, invisible
to the host, and inflates the container's writable layer.

**Permissions:** file logs are written by the `www-data` user. `/data/logs` is
prepared with the right ownership automatically. A custom path must be writable by
`www-data`; if the directory cannot be created or opened, the web server aborts at
startup and is restarted in a loop by the supervisor. There is no silent fallback.

---

## Persistence and rotation

There are two models, selectable per stream. Use **one sink per stream**: do not
send the same stream to both `stdout` and a file, or you double the storage and
the ingestion.

- **Stream to stdout/stderr (default).** Logs are ephemeral inside the container.
  Persistence and rotation are the responsibility of the Docker log driver or the
  orchestrator. Bound the size explicitly, otherwise the default `json-file`
  driver grows without limit:

  ```yaml
  services:
    humhub:
      logging:
        driver: local          # binary, compressed, auto-rotated
        options:
          max-size: "10m"
          max-file: "5"
  ```

- **Write to a file on `/data`.** Set the relevant `*_OUTPUT=file`. Files live in
  `/data/logs` (persisted with the volume) and are rotated by Caddy using the
  `*_ROLL_SIZE` / `*_ROLL_KEEP` settings.

The HumHub file log (`app.log`) is always rotated by Yii (10 MB, 5 files). The
database log is pruned daily to a 7 day retention by a HumHub cron job.

---

## Providers and consumers

**Providers:** the web server (Caddy/FrankenPHP), the PHP runtime, HumHub (Yii
`FileTarget` and `DbTarget`), the queue worker and scheduler scripts, and — in a
typical Compose setup — the MariaDB container.

**Consumers:**

- `docker logs <container>` for ad-hoc inspection.
- Any Docker log driver: `local`, `json-file`, `journald`, `syslog`, `fluentd`.
- Aggregators reading the stream: Loki/Promtail, Fluent Bit, Vector, the ELK stack.
- The HumHub admin Logging page (database target) for product-level events.

Because the default output is structured JSON on `stdout`/`stderr`, most
aggregators can consume it with no additional in-container configuration.

### Telling sources apart on the container stream

This all-in-one image runs several processes under a supervisor, so a single
stream can interleave output from the web server, the worker and the scheduler.
Distinguish them, in order of reliability:

1. **Process prefix** — the scheduler, worker and (when enabled) the `app.log`
   mirror prefix every line with their supervisor process name, e.g.
   `[humhub-scheduler]`, `[humhub-worker_00]`, `[humhub-app-log]`. With more than
   one worker each instance is distinct (`_00`, `_01`, ...).
2. **JSON fields** — the web server tags entries with a `logger` (for example
   `http.log.access.*` for the access log) and a `level`.
3. **The stream** — access log on `stdout`, diagnostics/PHP errors on `stderr`.
4. **A collector label** — have your log agent tag lines with the container name
   and stream.

If you need strict per-process separation, run the split topology in
`examples/compose-multi-services.yml`, where the web server, worker and cron run
as separate containers and therefore have separate log streams. That is the more
container-native setup and the recommended one for larger production deployments.

### How Docker handles stdout/stderr

The container's PID 1 `stdout`/`stderr` are captured by the container runtime and
handed to the configured **logging driver**. The default `json-file` driver writes
`/var/lib/docker/containers/<id>/<id>-json.log`, tagging each line with its
`stream` (stdout/stderr) and a timestamp, and **does not rotate by default**.

Enterprise production baseline:

- Set a bounded driver as a floor: `local` (recommended) or `json-file` with
  `max-size`/`max-file`, ideally daemon-wide in `/etc/docker/daemon.json`.
- Ship centrally with a node agent (Fluent Bit / Vector / Promtail) or a driver
  (`journald`, `syslog`, `fluentd`, `awslogs`, `gelf`), adding labels
  (service, environment, container).
- Keep logs structured (JSON) so the collector parses without regex.

On Kubernetes the kubelet owns capture and rotation of container stdout/stderr and
a DaemonSet agent collects them; the same principles apply with different plumbing.

### Example: JSON access log line

```json
{"level":"info","ts":1700000000.0,"logger":"http.log.access","msg":"handled request","request":{"method":"GET","uri":"/dashboard","proto":"HTTP/2.0","remote_ip":"203.0.113.10"},"status":200,"duration":0.0421}
```

### Example: switch access and server logs to files

```yaml
    environment:
      - HUMHUB_DOCKER__ACCESS_LOG_OUTPUT=file
      - HUMHUB_DOCKER__SERVER_LOG_OUTPUT=file
```

Both files then appear in `/data/logs` (host: `./humhub-data/logs`) and are
rotated automatically.
