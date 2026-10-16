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

The URL follows `SERVER_NAME`, because that variable decides how Caddy listens:

| `SERVER_NAME` | URL probed |
|---|---|
| unset, `localhost`, `https://humhub.example.com` | `https://localhost` |
| `https://humhub.example.com:8443` | `https://localhost:8443` |
| `http://humhub.example.com` | `http://localhost` |
| `http://humhub.example.com:8080` | `http://localhost:8080` |
| `:80`, `:8080` | `http://localhost:80`, `http://localhost:8080` |
| several addresses, `https://a.example.com, https://b.example.com` | the first one, `https://localhost` |

So a container behind a reverse proxy that terminates TLS (`SERVER_NAME=:80` or `http://…`) is probed over plain
HTTP, which is the only way it listens.

## Overriding the URL

`HUMHUB_DOCKER__HEALTHCHECK_URL` (empty by default) replaces the derived URL, for a setup the table does not cover
or to probe a specific path:

```yaml
    environment:
      - HUMHUB_DOCKER__HEALTHCHECK_URL=http://localhost:8080/user/auth/login
```

The probe runs inside the container, so `localhost` is the container itself.
