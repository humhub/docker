# Health check

The image ships `/app/bin/humhub-simple-healthcheck.sh`, a probe that reports whether the web server of the
container answers. It is not enabled by default: declare it in your `compose.yml` when something depends on the
container being up, for example a split topology where the scheduler and the workers wait for the web container
(`examples/compose-multi-services.yml`), or an orchestrator that routes traffic by health.

```yaml
services:
  humhub:
    image: humhub/humhub:stable
    # ...
    healthcheck:
      test: ["CMD", "/app/bin/humhub-simple-healthcheck.sh"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
```

The script requests one URL with `curl` (2 second timeout, self-signed certificates accepted) and exits 0 when the
answer is below HTTP 400.

## Which URL is probed

The URL follows the first address of `SERVER_NAME`, because that variable decides how Caddy listens:

| `SERVER_NAME` | URL probed |
|---|---|
| unset, `localhost` | `https://localhost` |
| `https://humhub.example.com`, `humhub.example.com` | `https://humhub.example.com` |
| `https://humhub.example.com:8443` | `https://humhub.example.com:8443` |
| `http://humhub.example.com[:8080]` | `http://humhub.example.com[:8080]` |
| `humhub.example.com:80` | `http://humhub.example.com:80` |
| `:80`, `:8080` | `http://localhost:80`, `http://localhost:8080` |
| several addresses, `https://a.example.com, https://b.example.com` | the first one, `https://a.example.com` |

The request is always sent to `127.0.0.1` inside the container, but keeps the host name for TLS (SNI) and the
`Host` header, so Caddy answers with the actual HumHub site. A container behind a reverse proxy that terminates TLS
(`SERVER_NAME=:80` or `http://...`) is probed over plain HTTP, which is the only way it listens.

An HTTPS address with an IP instead of a host name (`https://192.168.1.10`) cannot be probed this way, because no
host name is sent for TLS.

## Overriding the URL

`HUMHUB_DOCKER__HEALTHCHECK_URL` (empty by default) replaces the derived URL, for a setup the table does not cover
or to probe a specific path. It is requested as is, without redirecting the connection to `127.0.0.1`:

```yaml
    environment:
      - HUMHUB_DOCKER__HEALTHCHECK_URL=http://localhost:8080/user/auth/login
```

The probe runs inside the container, so `localhost` is the container itself.
