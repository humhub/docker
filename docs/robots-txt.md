# Custom robots.txt

The image does not ship a `robots.txt` by default. If you want to control how
search engines crawl your instance — for example to **disallow all crawlers** on
a staging or internal site — you have two options that work **without rebuilding
the image**.

The web server is [FrankenPHP](https://frankenphp.dev) (Caddy). Caddy serves
existing static files in the web root (`/app/public`) directly, and the
entrypoint also lets you inject your own Caddy directives via the
`CADDY_SERVER_EXTRA_DIRECTIVES` environment variable.

## Option 1 — Mount a file (recommended)

Place a `robots.txt` in the web root with a read-only bind mount. It is served
as-is and takes precedence over HumHub's routing.

```yaml
services:
  humhub:
    image: humhub/humhub:stable-nightly
    volumes:
      - ./humhub-data:/data
      - ./robots.txt:/app/public/robots.txt:ro
    # ...
```

`robots.txt` to disallow all crawlers:

```
User-agent: *
Disallow: /
```

> **Note:** Create the `robots.txt` file **before** `docker compose up`. If the
> host path does not exist, Docker creates a *directory* with that name instead.

## Option 2 — Answer it inline from Caddy (no file)

If you prefer not to mount a file, let Caddy respond to `/robots.txt` directly.
The entrypoint appends your `CADDY_SERVER_EXTRA_DIRECTIVES` to its own directives
(this is the same mechanism used internally for e.g. `respond /uploads/file/* 403`).

```yaml
services:
  humhub:
    image: humhub/humhub:stable-nightly
    environment:
      - SERVER_NAME=https://humhub.example.com
      # ... your other variables ...
      - |
        CADDY_SERVER_EXTRA_DIRECTIVES=respond /robots.txt 200 {
          body `User-agent: *
        Disallow: /`
        }
  db:
    image: mariadb
    # ... rest of the db service ...
```

The value uses Caddy's backtick raw-string syntax so the response body keeps its
line break.

> **Watch the indentation — this multi-line YAML is the easy thing to get wrong:**
> - The list item must be a literal block scalar (`- |`).
> - `Disallow: /` and the closing `}` sit at the **base indentation** of the
>   block (same column as the `CADDY_...` line). Extra spaces would leak into the
>   robots.txt body.
> - Sibling services such as `db:` must stay aligned with `humhub:` (2 spaces
>   under `services:`). A stray extra space there triggers a
>   `did not find expected key` parse error.
>
> If this feels fiddly, use **Option 1** — a mounted file avoids multi-line YAML
> entirely.

## Verify

After starting the container:

```bash
curl -k https://humhub.example.com/robots.txt
```

Expected output:

```
User-agent: *
Disallow: /
```

## Hard-blocking crawlers

`robots.txt` is only a *request* — well-behaved crawlers honor it, but it does
not enforce anything. To actually reject traffic (e.g. from a specific bot), add
a matcher to `CADDY_SERVER_EXTRA_DIRECTIVES`, for example:

```
@badbots header User-Agent *SomeBot*
respond @badbots 403
```
