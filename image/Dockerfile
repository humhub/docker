# ======================================
# Stage 1: Build HumHub
# ======================================
FROM debian:bookworm AS builder

ARG HUMHUB_GIT_BRANCH="develop"

RUN apt-get update && apt-get install -y \
    git curl unzip zip npm php-cli php-ldap php php-mbstring php-intl php-gd php-zip php-curl php-xml php-bz2 php-apcu \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && npm install -g grunt-cli less less-plugin-clean-css

WORKDIR /opt/humhub

RUN git clone https://github.com/humhub/humhub.git . && \
    git checkout ${HUMHUB_GIT_BRANCH} && \
    composer install --no-interaction --optimize-autoloader --prefer-dist && \
    npm install && \
    grunt build-assets && \
    rm -Rf .git/

# ======================================
# Stage 2: Runtime with FrankenPHP + Supervisor
# ======================================
FROM dunglas/frankenphp:1-php8.4

USER root
#RUN apt-get update && apt-get install -y supervisor bash && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y supervisor bash procps joe mariadb-client

WORKDIR /app

RUN install-php-extensions \
	pdo_mysql \
	gd \
	intl \
	exif \
	imagick \
	ldap \
	zip \
	opcache \
	apcu

COPY --from=builder /opt/humhub /opt/humhub

# --- Supervisor config ---
COPY files/supervisord.conf /etc/supervisor/conf.d/humhub.conf

# --- HumHub scripts ---
COPY files/index.php /app/public/
COPY files/yii-wrapper /app/yii
COPY files/docker-entrypoint.sh /
COPY files/yii files/humhub-worker.sh files/humhub-scheduler.sh files/humhub-startup.sh files/humhub-backup.sh files/humhub-simple-healthcheck.sh files/humhub-app-log.sh /app/bin/
RUN chmod +x /docker-entrypoint.sh /app/yii /app/bin/yii /app/bin/humhub-worker.sh /app/bin/humhub-scheduler.sh /app/bin/humhub-startup.sh /app/bin/humhub-backup.sh /app/bin/humhub-simple-healthcheck.sh /app/bin/humhub-app-log.sh


RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp; \
    chown -R www-data:www-data /config/caddy /data/caddy

# --- HumHub paths ---
RUN mkdir -p /data \
    && mkdir -p /app/runtime/ \
    && rm -rf /app/runtime/logs \
    && ln -s /data/logs/ /app/runtime/logs \
    && ln -s /data/uploads/ /app/public/uploads \
    && ln -s /data/assets/ /app/public/assets \
    && ln -s /data/themes/ /app/public/themes \
    && ln -s /opt/humhub/static/ /app/public/static

# --- Environment ---
ENV HUMHUB_DOCKER=true \
    HUMHUB_DOCKER__MERCURE_ENABLE=true \
    HUMHUB_CONFIG__COMPONENTS__URL_MANAGER__SHOW_SCRIPT_NAME=false \
    HUMHUB_CONFIG__COMPONENTS__URL_MANAGER__ENABLE_PRETTY_URL=true \
    HUMHUB_CONFIG__MODULES__INSTALLER__ENABLE_AUTO_SETUP=false \
    HUMHUB_CONFIG__MODULES__MARKETPLACE__MODULE_BLACKLIST='["updater"]' \
    HUMHUB_CONFIG__MODULES__MARKETPLACE__MODULES_PATH=/data/modules \
    HUMHUB_CONFIG__PARAMS__MODULE_AUTOLOAD_PATHS='["/data/modules-custom", "/data/modules"]' \
    HUMHUB_CONFIG__RUNTIME_PATH=/app/runtime \
    HUMHUB_ALIASES__WEBROOT=/app/public \
    HUMHUB_ALIASES__APP=/opt/humhub/protected \
    HUMHUB_ALIASES__CONFIG=/data/config \
    HUMHUB_ALIASES__HUMHUB=/opt/humhub/protected/humhub \
    HUMHUB_DOCKER__AUTOSTART_FRANKENPHP=true \
    HUMHUB_DOCKER__AUTOSTART_SCHEDULER=true \
    HUMHUB_DOCKER__AUTOSTART_WORKER=true \
    HUMHUB_DOCKER__NUMPROCS_WORKER=2 \
    HUMHUB_DOCKER__ACCESS_LOG=false \
    HUMHUB_DOCKER__ACCESS_LOG_FORMAT=json \
    HUMHUB_DOCKER__ACCESS_LOG_TARGET=stdout \
    HUMHUB_DOCKER__ACCESS_LOG_FILE=/data/logs/access.log \
    HUMHUB_DOCKER__ACCESS_LOG_ROLL_SIZE=100MiB \
    HUMHUB_DOCKER__ACCESS_LOG_ROLL_KEEP=5 \
    HUMHUB_DOCKER__SERVER_LOG=true \
    HUMHUB_DOCKER__SERVER_LOG_LEVEL=INFO \
    HUMHUB_DOCKER__SERVER_LOG_FORMAT=json \
    HUMHUB_DOCKER__SERVER_LOG_TARGET=stderr \
    HUMHUB_DOCKER__SERVER_LOG_FILE=/data/logs/server.log \
    HUMHUB_DOCKER__ENABLE_APP_LOG_TO_STDOUT=true

# --- Startup ---
CMD ["/docker-entrypoint.sh"]