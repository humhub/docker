# Without Docker Compose

```bash
docker run \
      --name humhub \
      --publish 80:80 \
      --publish 443:443 \
      --publish 443:443/udp \
      -e HUMHUB_DEBUG=true \
      -e SERVER_NAME=https://humhub.example.com \
      --volume ./humhub-data:/data \
      humhub/humhub:stable
```

