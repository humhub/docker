# Additional PHP Extensions

Some HumHub modules need PHP extensions beyond those required by HumHub core.
The image ships the core extensions plus a few small ones commonly needed by modules.
Anything else can be added by building a small derived image.

---

## Common Built-in Extensions

The following table lists the most common extensions the image adds on top of the PHP defaults.
It is not complete, and the set of extensions may change with future image versions.

| Extension   | Purpose                                                            |
|-------------|--------------------------------------------------------------------|
| `pdo_mysql` | Database access                                                    |
| `gd`        | Image processing                                                   |
| `imagick`   | Image processing (ImageMagick)                                     |
| `intl`      | Internationalization                                               |
| `exif`      | Image metadata                                                     |
| `ldap`      | LDAP authentication                                                |
| `zip`       | Archive handling (e.g. module installation)                        |
| `opcache`   | Bytecode cache                                                     |
| `apcu`      | In-memory cache                                                    |
| `bcmath`    | Arbitrary precision math (e.g. Push Notifications, JWT/OIDC logins) |
| `gmp`       | Arbitrary precision math (faster alternative used by some libraries) |
| `sockets`   | Low-level socket access (e.g. Virus Scanner)                       |

The full list of extensions built into your HumHub image can be viewed with:

```bash
docker compose exec humhub php -m
```

---

## Adding Extensions

The image is based on [FrankenPHP](https://frankenphp.dev), which provides the
[`install-php-extensions`](https://github.com/mlocati/docker-php-extension-installer) helper.
It installs any core or PECL extension together with its system libraries.

**Example**

The following example shows one way of adding the `soap` and `bz2` extensions.
First, create a `Dockerfile` in the same directory as your `docker-compose.yml`:

```dockerfile
FROM humhub/humhub:stable

RUN install-php-extensions soap bz2
```

Then, in your `docker-compose.yml`, add `build: .` to the `humhub` service and give the built image its own name:

```yaml
services:
  humhub:
    build: .
    image: humhub-custom:stable
    # ... remaining settings unchanged
```

Next, build the image and start the containers:

```bash
docker compose build --pull
docker compose up -d
```

Finally, verify that the extensions are loaded:

```bash
docker compose exec humhub php -m | grep -i -E 'soap|bz2'
```

---

## Upgrading

The derived image is not updated by `docker compose pull`.
Rebuild it whenever you upgrade HumHub, so it picks up the new base image:

```bash
docker compose build --pull
docker compose up -d
```

To pin a specific HumHub version, use a version tag in the `FROM` line (e.g. `humhub/humhub:1.18`),
see [Docker Image Tagging Policy](docker-image-tagging-policy.md).

---

## Notes

- The [Redis Integration](redis.md) does not need the `redis` PHP extension;
  HumHub core uses a pure PHP Redis client.
- Install extensions at build time only. Installing them at container start is slow,
  requires network access and does not work with read-only or rootless setups.
- If an extension you need is small and useful for many installations, consider
  opening an issue at [humhub/docker](https://github.com/humhub/docker/issues) to have it included by default.
