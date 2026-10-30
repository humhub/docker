# TLS Configuration

The container terminates TLS itself. Caddy (the web server inside FrankenPHP) decides how by the `SERVER_NAME`
variable:

| `SERVER_NAME` | Behaviour |
|---|---|
| `humhub.example.com` or `https://humhub.example.com` | HTTPS for this host, certificate from Let's Encrypt (default) |
| same, plus `tls ...` in `CADDY_SERVER_EXTRA_DIRECTIVES` | HTTPS with your own certificate or the internal CA |
| `:80` or `http://humhub.example.com` | Plain HTTP, only behind a reverse proxy |

Certificates, keys and the internal CA are stored in `/data/caddy`, so they persist with the data volume.

The examples below only show the relevant parts of the `humhub` service from the
[Quick Start](../README.md#quick-start).

## Automatic certificates (default)

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
- `/data` is persistent. Without it, every new container requests new certificates and can run into the
  Let's Encrypt rate limits.

## Own certificate

Mount the certificate and key, and point Caddy to them:

```yaml
services:
  humhub:
    volumes:
      - ./humhub-data:/data
      - ./certs:/certs:ro
    environment:
      - SERVER_NAME=humhub.example.com
      - CADDY_SERVER_EXTRA_DIRECTIVES=tls /certs/fullchain.pem /certs/privkey.pem
```

- The certificate file contains the full chain (server certificate first, then the intermediates).
- Both files must be readable by uid 33 (`www-data`), which runs Caddy.

### Self-signed certificate

For test and internal setups:

```bash
mkdir -p certs
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=humhub.example.com" \
  -addext "subjectAltName=DNS:humhub.example.com" \
  -keyout certs/privkey.pem -out certs/fullchain.pem
chmod 644 certs/*.pem
```

Use the same compose configuration as above. Browsers show a warning until `fullchain.pem` is imported as
trusted certificate.

### Renewing the certificate

Caddy does not watch the files. After replacing them, restart the container:

```bash
docker compose restart humhub
```

> Do not run `frankenphp reload` inside the container. It loads the new certificate, but the reloaded
> configuration lacks the settings the image generates at startup (e.g. access protection for
> `/uploads/file`, live updates, logging).

## Internal CA

Caddy can issue certificates from its own local CA, e.g. for test setups or as the backend of a reverse proxy:

```yaml
    environment:
      - SERVER_NAME=humhub.example.com
      - CADDY_SERVER_EXTRA_DIRECTIVES=tls internal
```

Server certificates are short-lived and renewed automatically. Clients that should trust them import the root
certificate from `humhub-data/caddy/pki/authorities/local/root.crt`. The root stays the same as long as
`/data/caddy` is kept.

## Behind a reverse proxy

General topics (trusted hosts, forwarded headers, Base URL) are covered in the
[HumHub reverse proxy documentation](https://docs.humhub.org/docs/admin/reverse-proxy). On the container side
there are three options:

| Option | HumHub container | Trusted hosts needed for |
|---|---|---|
| **Re-encrypt** (recommended) | `SERVER_NAME=humhub.example.com`, `tls internal` | visitor IP only |
| **TLS passthrough** | unchanged (automatic certificates) | nothing (visitor IP via PROXY protocol) |
| **Plain HTTP** | `SERVER_NAME=:80` | scheme, host and visitor IP |

In all cases the container does not publish ports. It joins a Docker network shared with the proxy:

```yaml
services:
  humhub:
    networks: [default, proxy]

networks:
  proxy:
    external: true  # docker network create proxy
```

The [health check](healthcheck.md) follows `SERVER_NAME` and works with all three options.

### Re-encrypt (recommended)

The proxy terminates the public TLS connection and connects to the container via HTTPS. HumHub sees a secure
connection with the original host name, so it generates correct `https://` URLs without trusting any
forwarded headers.

```yaml
services:
  humhub:
    networks: [default, proxy]
    environment:
      - SERVER_NAME=humhub.example.com
      - CADDY_SERVER_EXTRA_DIRECTIVES=tls internal
```

The proxy must:

1. keep the original `Host` header,
2. send the host name as SNI,
3. trust the container's root certificate (`/data/caddy/pki/authorities/local/root.crt`).

Example with Caddy as proxy:

```yaml
services:
  caddy:
    image: caddy:2
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy-data:/data
      - /opt/humhub/humhub-data/caddy/pki/authorities/local/root.crt:/humhub-root.crt:ro
    networks: [proxy]

networks:
  proxy:
    external: true
```

```caddyfile
humhub.example.com {
	reverse_proxy https://humhub:443 {
		header_up Host {host}
		transport http {
			tls_server_name humhub.example.com
			tls_trust_pool file /humhub-root.crt
		}
	}
}
```

`header_up Host {host}` is required: for HTTPS upstreams Caddy otherwise sends `Host: humhub:443`.
Configurations for nginx, Apache and Traefik: see the core documentation.

If the root certificate changes (e.g. `/data/caddy` was lost), restart the proxy.

HumHub sees the proxy as client. For the real visitor IP, add the proxy network as trusted host, as shown under
[Plain HTTP](#plain-http).

### TLS passthrough

The proxy forwards the TLS connection unchanged, based on the SNI host name (e.g. Traefik TCP router with
`passthrough`, nginx `stream` with `ssl_preread`). The container keeps its default configuration and obtains its
certificates itself. The proxy forwards TCP ports 80 and 443.

The proxy cannot add headers to an encrypted connection, so the visitor IP is only available via the PROXY
protocol. Enable it on the proxy for port 443 only, and accept it in the container:

```yaml
    environment:
      CADDY_GLOBAL_OPTIONS: |
        servers {
          listener_wrappers {
            proxy_protocol {
              allow 172.18.0.0/16
            }
            tls
          }
        }
```

Replace `172.18.0.0/16` with the subnet of the proxy network (`docker network inspect proxy`).

### Plain HTTP

Only use this if proxy and container run on the same host.

```yaml
services:
  humhub:
    networks: [default, proxy]
    environment:
      - SERVER_NAME=:80
      - HUMHUB_WEB_CONFIG__COMPONENTS__REQUEST__TRUSTED_HOSTS=["172.18.0.0/16"]
```

- `SERVER_NAME=http://humhub.example.com` instead of `:80` answers only for this host name.
- The proxy network must be a trusted host, otherwise HumHub generates `http://` URLs (mixed content, broken
  live updates).
- The proxy must send `X-Forwarded-Proto` and `X-Forwarded-Host`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Links and redirects use `http://` | Plain HTTP without trusted hosts, or proxy sends no `X-Forwarded-Proto` | Configure trusted hosts, send the header |
| URLs contain `:80` | Proxy sends no `X-Forwarded-Host` | Send the header |
| HTTP 500, container unhealthy after setting trusted hosts | Single quotes in the list syntax (`- KEY='[...]'`) become part of the value | List syntax without quotes, or map syntax `KEY: '["..."]'` |
| Web works, but scheduler and workers log `HumHub not installed yet` | Trusted hosts set via `HUMHUB_CONFIG__...`, which breaks every `yii` command | Use the `HUMHUB_WEB_CONFIG__` prefix |
| Empty page (HTTP 200, no content) | Proxy does not keep the `Host` header | Keep it (Caddy: `header_up Host {host}`) |
| Proxy reports `tls: internal error` / `tlsv1 alert internal error` | Proxy sends no or a wrong SNI | Send the host name as SNI |
| Proxy reports `unknown authority` | Container root certificate not trusted, or it has changed | Mount `root.crt`, restart the proxy |
| Access log or HumHub shows the proxy IP | Visitor IP not trusted | Trusted hosts in HumHub, for the access log see [Logging](logging.md#client-ip-behind-a-reverse-proxy) |
| New certificate not used | Caddy does not watch certificate files | Restart the container |
