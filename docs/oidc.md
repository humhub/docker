# OpenID Connect (OIDC) Single Sign-On

This image ships with built-in, environment-driven OpenID Connect support. Any
standards-compliant identity provider (Keycloak, Authentik, Zitadel, Azure
Entra ID, Auth0, …) that exposes a `.well-known/openid-configuration` discovery
document can be used as an external login provider for HumHub.

OIDC is powered by HumHub's bundled [`yii2-authclient`](https://www.yiiframework.com/extension/yiisoft/yii2-authclient)
`OpenIdConnect` client. The required JWT libraries (`web-token/jwt-library`) are
already part of the image, so signature validation (`validateJws`) works out of
the box.

## Quick start

Add the following environment variables to your `humhub` service and restart:

```yaml
services:
  humhub:
    environment:
      - SERVER_NAME=https://humhub.example.com
      - OIDC_ENABLE=true
      - OIDC_ISSUER_URL=https://keycloak.example.com/realms/humhub
      - OIDC_CLIENT_ID=humhub
      - OIDC_CLIENT_SECRET=__from_your_idp__
      - OIDC_TITLE=Login via SSO
```

A ready-to-use example is provided in
[`examples/compose-oidc.yml`](../examples/compose-oidc.yml).

At the identity provider, register this **redirect / callback URL**:

```
https://<SERVER_NAME>/user/auth/external?authclient=<OIDC_ID>
```

With the default `OIDC_ID` (`oidc`) and the example above this is:

```
https://humhub.example.com/user/auth/external?authclient=oidc
```

## Environment variables

| Variable             | Required | Default          | Description                                                                                |
|----------------------|----------|------------------|--------------------------------------------------------------------------------------------|
| `OIDC_ENABLE`        | yes      | `false`          | Master switch. Must be truthy (`true`/`1`) to register the client.                         |
| `OIDC_ISSUER_URL`    | yes      | –                | Base URL of the IdP used for discovery, e.g. `https://keycloak.example.com/realms/humhub`. |
| `OIDC_CLIENT_ID`     | yes      | –                | OAuth2 client id registered at the IdP.                                                    |
| `OIDC_CLIENT_SECRET` | yes      | –                | OAuth2 client secret. Inject via a secret, do not commit it.                               |
| `OIDC_ID`            | no       | `oidc`           | Internal id of the auth client. Appears in the callback URL (`?authclient=<id>`).          |
| `OIDC_TITLE`         | no       | `SSO Login`      | Label shown on the login button.                                                           |
| `OIDC_VALIDATE_JWS`  | no       | `true`           | Verify the ID-token signature against the IdP JWKS. Keep enabled in production.            |
| `OIDC_SCOPE`         | no       | (client default) | Space-separated scopes, e.g. `openid profile email`.                                       |

If `OIDC_ENABLE` is true but any of the three required values is missing, the
client is **not** registered (HumHub starts normally without OIDC).

## How it works (and why the file is named `common.php`)

HumHub's `BootstrapService` loads configuration from `/data/config` but only
reads a **fixed set of file names**: `common.php`, `web.php` / `console.php`
and (optionally) `dynamic.php`. Arbitrary files such as `oidc.php` are **not**
picked up automatically, and `dynamic.php` is owned/rewritten by HumHub's own
installer — so neither is a safe place for our config.

Therefore the image ships a managed `common.php` (see
[`image/files/config/common.php`](../image/files/config/common.php)) that builds
the OIDC auth client from the environment variables above **at runtime**. It is:

- copied to `/data/config/common.php` on first start, and
- refreshed on every container start as long as it still carries the
  `@humhub-docker:managed` marker (so image upgrades keep it current).

This answers the common questions:

- **Can it be generated dynamically at container start?** Yes — that is exactly
  what happens. The entrypoint installs/refreshes the file, and because the file
  reads `getenv()` at runtime, you only need to change the compose environment
  and restart; no file editing is required.
- **Does the file have to be called `common.php`?** Yes, for it to be loaded
  automatically. `web.php`/`console.php` would also be loaded but are
  mode-specific; `dynamic.php` is reserved by HumHub.
- **Could it be `oidc.php` instead?** Only indirectly: a standalone `oidc.php`
  is ignored by the loader. You would have to `require`/merge it from
  `common.php`. The managed `common.php` already provides such a hook — see
  below.

## Customising the configuration

Do **not** edit the managed `common.php` directly — it is overwritten on every
start. Instead create `/data/config/common.local.php`; it is merged on top of
the generated config and never touched by the image:

```php
<?php
// /data/config/common.local.php
return [
    'components' => [
        'authClientCollection' => [
            'clients' => [
                'oidc' => [
                    // Override or extend anything from the env-generated client,
                    // e.g. attribute mapping or extra scopes.
                    'scope' => 'openid profile email groups',
                ],
            ],
        ],
    ],
];
```

If you prefer to fully manage the config yourself, remove the
`@humhub-docker:managed` marker line from `/data/config/common.php`; the image
will then stop overwriting it.

## Troubleshooting

- **Signature errors / `validateJws`**: ensure the container can reach the IdP's
  JWKS endpoint. The `gmp` and `openssl` PHP extensions required for RSA/ECDSA
  signatures are included in the image.
- **Redirect URI mismatch**: the callback registered at the IdP must match
  `https://<SERVER_NAME>/user/auth/external?authclient=<OIDC_ID>` exactly,
  including scheme and host. Make sure `SERVER_NAME` is set correctly.
- **Button not shown**: check `OIDC_ENABLE=true` and that all required values
  are set. Inspect the rendered config with
  `docker compose exec humhub /app/yii settings/list` or enable `HUMHUB_DEBUG`.
