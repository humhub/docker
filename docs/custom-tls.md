# TLS Configuration

The container terminates TLS itself, using [Caddy](https://caddyserver.com), the web server inside
[FrankenPHP](https://frankenphp.dev). The `SERVER_NAME` variable sets the host name. The certificate comes from
one of three sources:

- [Automatic certificates](#automatic-certificates-default) and the [internal CA](#internal-ca) are provided
  directly by the image. They need no certificate files, are renewed automatically and suit most setups.
- [Own certificates](#own-certificate) are only needed if you have to use certificates from another source.

Host paths refer to the [Quick Start](../README.md#quick-start) bind mount `./humhub-data:/data`:
`humhub-data/...` on the host is `/data/...` in the container. The examples only show the relevant parts of the
`humhub` service.

## Automatic certificates (default)

Caddy obtains a certificate from Let's Encrypt and renews it automatically.

Configuration:

- `SERVER_NAME=humhub.example.com` (or `https://humhub.example.com`)

```yaml
services:
  humhub:
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3 (optional)
    volumes:
      - ./humhub-data:/data
    environment:
      - SERVER_NAME=humhub.example.com
```

Requirements:

- The DNS record of `humhub.example.com` points to the host.
- Ports 80 and 443 are reachable from the internet (ACME challenges).
- `humhub-data` is persistent. Caddy stores certificates, keys and ACME account in `humhub-data/caddy/`. Without
  it, every new container requests new certificates and can run into the Let's Encrypt rate limits.

## Internal CA

Caddy issues certificates from its own local CA, e.g. for test setups or as the backend of a reverse proxy.

Configuration:

- `SERVER_NAME=humhub.example.com`
- `CADDY_SERVER_EXTRA_DIRECTIVES=tls internal`

```yaml
    environment:
      - SERVER_NAME=humhub.example.com
      - CADDY_SERVER_EXTRA_DIRECTIVES=tls internal
```

Server certificates are short-lived and renewed automatically. Clients that should trust them import the root
certificate `humhub-data/caddy/pki/authorities/local/root.crt`. It stays the same as long as `humhub-data/caddy`
is kept.

The [backup script](backup-restore.md) of the image does not include `humhub-data/caddy/`. Back up
`humhub-data/caddy/pki/` separately, otherwise a restore creates a new root certificate, and clients and reverse
proxies that trust the old one have to import the new one.

## Own certificate

Own certificates are certificates you provide instead of letting Caddy obtain them, for example issued by a
public or commercial CA, by your own CA (e.g. a company PKI), or [self-signed](#self-signed-certificate).

Configuration:

- `SERVER_NAME=humhub.example.com`
- `CADDY_SERVER_EXTRA_DIRECTIVES=tls <certificate> <key>`
- Create the folder `humhub-data/certs/` on the host if it does not exist, and place both files there

```yaml
services:
  humhub:
    volumes:
      - ./humhub-data:/data
    environment:
      - SERVER_NAME=humhub.example.com
      - CADDY_SERVER_EXTRA_DIRECTIVES=tls /data/certs/fullchain.pem /data/certs/privkey.pem
```

- The certificate file contains the full chain (server certificate first, then the intermediates).
- On startup the container changes the owner of all files in `humhub-data` to uid 33 (`www-data`, which runs
  Caddy), including these files.
- The [backup script](backup-restore.md) of the image does not include `humhub-data/certs/`. Back up certificate
  and key separately.

> Do not place own certificates in `humhub-data/caddy/`. Caddy uses this folder (`/data/caddy` in the container)
> as its managed storage for certificates, keys, OCSP staples and ACME state. It scans the storage at startup and
> then every 24 hours, and removes old or expired assets as well as files it does not recognize (see
> [data directory](https://caddyserver.com/docs/conventions#data-directory) and
> [storage_clean_interval](https://caddyserver.com/docs/caddyfile/options#storage-clean-interval)).

### Self-signed certificate

For test and internal setups:

```bash
mkdir -p humhub-data/certs
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=humhub.example.com" \
  -addext "subjectAltName=DNS:humhub.example.com" \
  -keyout humhub-data/certs/privkey.pem -out humhub-data/certs/fullchain.pem
```

Use the same compose configuration as above. Browsers show a warning until `fullchain.pem` is imported as
trusted certificate.

### Renewing the certificate

Certificates loaded with the `tls` directive are not managed by Caddy
([tls directive](https://caddyserver.com/docs/caddyfile/directives/tls)): renewing or replacing them is your
responsibility. Caddy does not watch the files either. After replacing them, restart the container:

```bash
docker compose restart humhub
```

> Do not run `frankenphp reload` inside the container. It loads the new certificate, but the reloaded
> configuration lacks the settings the image generates at startup (e.g. access protection for
> `/uploads/file`, live updates, logging).

## Behind a reverse proxy

If a reverse proxy terminates the public TLS connection, the container either keeps HTTPS with the
[internal CA](#internal-ca) (re-encrypt, recommended), receives the TLS connection unchanged from the proxy
(passthrough), or serves plain HTTP with `SERVER_NAME=:80`. Setup, forwarded headers, trusted hosts and proxy
examples are described in the [HumHub reverse proxy documentation](https://docs.humhub.org/docs/admin/reverse-proxy).

Pitfalls specific to the Docker image:

- **Trusted hosts via environment variable:** use the `HUMHUB_WEB_CONFIG__` prefix. With `HUMHUB_CONFIG__`, every
  `yii` command fails, and scheduler and workers wait forever with `HumHub not installed yet`. Write the value
  without quotes:
  ```yaml
      environment:
        - HUMHUB_WEB_CONFIG__COMPONENTS__REQUEST__TRUSTED_HOSTS=["172.18.0.0/16"]
  ```
  This works in the compose `environment` list, in `env_file` files and with `docker run --env-file`. Only
  `env_file` removes quotes. Elsewhere, single quotes (`='[...]'`) become part of the value and cause HTTP 500
  errors.
- **Re-encrypt:** the proxy must send the host name as SNI and keep the original `Host` header, otherwise it
  reports `tls: internal error` (no SNI) or HumHub answers with an empty page (wrong `Host`).
- **Visitor IP:** HumHub sees the proxy as client until the proxy is a trusted host. Which address that is
  depends on the network setup, see [Logging](logging.md#client-ip-behind-a-reverse-proxy).
