<?php
/**
 * @humhub-docker:managed
 *
 * This file is managed by the humhub-docker image and is refreshed on every
 * container start (see docker-entrypoint.sh). DO NOT edit it directly – your
 * changes will be overwritten.
 *
 * To add your own configuration, create a file `common.local.php` in this same
 * directory (`/data/config/common.local.php`). It is merged on top of the
 * config built here and is never touched by the image.
 *
 * This file enables OpenID Connect (OIDC) single sign-on purely from
 * environment variables. See docs/oidc.md for details.
 *
 * @see https://docs.humhub.org/docs/admin/authentication
 * @see https://www.yiiframework.com/extension/yiisoft/yii2-authclient
 */

$config = [];

//----------------------------------------------------------------------
// OpenID Connect (OIDC) single sign-on
//----------------------------------------------------------------------
// Enabled when OIDC_ENABLE is truthy and the mandatory endpoints are set.
// All values are read at runtime, so changing the compose environment and
// restarting the container is enough – no file editing required.
if (filter_var(getenv('OIDC_ENABLE'), FILTER_VALIDATE_BOOLEAN)) {
    $issuerUrl = getenv('OIDC_ISSUER_URL') ?: null;
    $clientId = getenv('OIDC_CLIENT_ID') ?: null;
    $clientSecret = getenv('OIDC_CLIENT_SECRET') ?: null;

    if ($issuerUrl && $clientId && $clientSecret) {
        // Internal id/name of the auth client. Part of the callback URL:
        // https://<server>/user/auth/external?authclient=<id>
        $id = getenv('OIDC_ID') ?: 'oidc';

        $config['components']['authClientCollection']['clients'][$id] = [
            'class' => yii\authclient\OpenIdConnect::class,
            'id' => $id,
            'name' => $id,
            // Label shown on the login button.
            'title' => getenv('OIDC_TITLE') ?: 'SSO Login',
            // Base URL of the IdP, used for .well-known/openid-configuration
            // discovery, e.g. https://keycloak.example.com/realms/humhub
            'issuerUrl' => $issuerUrl,
            'clientId' => $clientId,
            'clientSecret' => $clientSecret,
            // Verify the ID-token signature against the IdP's JWKS. Requires the
            // web-token/jwt-library package, which HumHub already ships. Keep
            // this enabled in production; only disable for trusted loopback IdPs.
            'validateJws' => filter_var(
                getenv('OIDC_VALIDATE_JWS') ?: 'true',
                FILTER_VALIDATE_BOOLEAN,
            ),
        ];

        // Optional explicit scopes (space separated), e.g. "openid profile email".
        if ($scope = getenv('OIDC_SCOPE')) {
            $config['components']['authClientCollection']['clients'][$id]['scope'] = $scope;
        }
    }
}

//----------------------------------------------------------------------
// User overrides
//----------------------------------------------------------------------
// Anything in /data/config/common.local.php wins over the config above.
$localConfig = __DIR__ . '/common.local.php';
if (is_readable($localConfig)) {
    $config = yii\helpers\ArrayHelper::merge($config, require $localConfig);
}

return $config;
