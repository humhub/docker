docker run \
    --name humhub --rm \
    --publish 80:80 \
    --publish 443:443 \
    --publish 443:443/udp \
    -e HUMHUB_DEBUG=true \
    -e SERVER_NAME=http://localhost \
    --volume /tmp/humhub-data:/data \
    humhub/humhub:local
