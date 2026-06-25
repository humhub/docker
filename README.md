# HumHub – Official Docker Image

A ready-to-use Docker image for [HumHub](https://www.humhub.org) – the flexible open-source social networking platform.  
This image provides everything you need to run HumHub in a modern, containerized environment.


---

## Features

- Complete HumHub stack – preconfigured and production-ready
- Includes cron, queue workers and push events out of the box
- Secure defaults with automatic HTTPS certificates
- Simple setup with Docker Compose or any container platform
- Works with internal or external databases, Redis, or mail services
- Easy upgrading and version switching

---

## Quick Start

Create a project directory (for example `/opt/humhub`) and inside it a `docker-compose.yml` file with the following content:

```bash
mkdir -p /opt/humhub
cd /opt/humhub
```

```yaml
services:
  humhub:
    image: humhub/humhub:stable-nightly
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3 (optional)
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./humhub-data:/data
    environment:
      - HUMHUB_DEBUG=true
      - SERVER_NAME=https://humhub.example.com
      - HUMHUB_CONFIG__COMPONENTS__DB__DSN=mysql:host=db;dbname=humhub
      - HUMHUB_CONFIG__COMPONENTS__DB__USERNAME=root
      - HUMHUB_CONFIG__COMPONENTS__DB__PASSWORD=changeMe
  db:
    image: mariadb
    restart: unless-stopped
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    user: root
    volumes:
      - ./mysql-data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=changeMe
    expose:
      - "3306"
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck.sh", "--su-mysql", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
```

> **Important:**  
> Before starting the containers, make sure to **adjust all environment variables** in the example — especially passwords and domain names.  
> Never use the provided example values in production environments.
>
> Required changes include:
> - `HUMHUB_CONFIG__COMPONENTS__DB__PASSWORD`
> - `MYSQL_ROOT_PASSWORD`
> - `SERVER_NAME`

Once adjusted, start HumHub with:

```bash
docker compose up -d
```

Requires **Docker ≥ 20.10.13** with **Compose v2**.  
If you are using an older setup, use `docker-compose` instead.

Your instance installer will be available at:  
**https://humhub.example.com**

---

## More Docs

- [Upgrading HumHub](docs/upgrading.md)
- [Using the HumHub Console Interface](docs/cli.md)
- [Backup and Restore](docs/backup-restore.md)
- [Custom Themes and Modules](docs/custom-themes-modules.md)
- [Running Without Docker Compose](docs/manual-run.md)
- [Redis Integration](docs/redis.md)
- [Custom TLS Settings](docs/custom-tls.md)
- [OpenID Connect (OIDC) Single Sign-On](docs/oidc.md)



