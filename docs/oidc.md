# OIDC authentication

The image bundles [mlflow-oidc-auth](https://github.com/mlflow-oidc/mlflow-oidc-auth)
(`OIDC_AUTH_VERSION` in the `Makefile`), which turns the tracking server into
a SSO-protected application: users sign in through your identity provider
(Keycloak, Okta, Entra ID, Auth0, ...), programmatic clients use personal
access tokens, and permissions are grantable per user/group in the plugin's
admin UI.

## Enable it

Set at least these in `.env` and restart the stack (`make up`):

```bash
OIDC_DISCOVERY_URL=https://idp.example.com/.well-known/openid-configuration
OIDC_CLIENT_ID=mlflow
OIDC_CLIENT_SECRET=change-me
SECRET_KEY=change-me-too
```

When `OIDC_DISCOVERY_URL` is set, the entrypoint adds `--app-name oidc-auth`
to `mlflow server`; without it the server runs unauthenticated as before.

Register the client at your IdP first:

- **Client type**: confidential (client secret), authorization-code flow.
- **Redirect URI**: `<public MLflow URL>/callback`
  (e.g. `https://mlflow.example.com/callback`).
- **Scopes**: `openid`, `email`, `profile`.
- **Token claims**: the ID token must carry an email (or
  `preferred_username`) and a `groups` claim listing the user's groups.

The plugin keeps its user/permission database separately from the MLflow
tracking database:

```bash
# Default: sqlite file on the /data volume (mlflow_data), fine for a single
# worker (`MLFLOW_WORKERS=1`). For production, point it at MySQL/PostgreSQL:
OIDC_USERS_DB_URI=mysql+pymysql://mlflow:pass@db:3306/mlflow_auth
```

The schema is migrated automatically on startup. Users in an admin group
have full admin rights from their first login; the plugin also creates a
built-in admin account with a random password printed to the logs, for API
access before anyone has signed in.

## Exposed configuration

`docker-compose.yml` forwards the most common plugin variables; everything
else (sessions, SCIM, workspaces, cache, ...) can be set by extending the
`mlflow` service with a `docker-compose.override.yml` or
`docker compose -f ...` overlay. Full reference:
<https://mlflow-oidc.github.io/mlflow-oidc-auth/>.

| Variable | Default | Notes |
| --- | --- | --- |
| `OIDC_DISCOVERY_URL` | — | Enables OIDC when set |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | — | Client credentials (`OIDC_PUBLIC_CLIENT=true` for secret-less PKCE clients) |
| `SECRET_KEY` | random per start | Signs session cookies; **must be shared** across replicas and kept stable, otherwise logins drop on restart |
| `OIDC_REDIRECT_URI` | auto-detected | Only needed behind a proxy that does not send usable forwarded headers |
| `OIDC_SCOPE` | `openid,email,profile` | |
| `OIDC_USERNAME_FIELD` | `email,preferred_username` | Claim used as the account name |
| `OIDC_GROUP_NAME` | `mlflow` | Comma-separated groups allowed to log in |
| `OIDC_GROUP_NAME_PATTERN` | empty | Shell-style patterns, e.g. `mlflow-*` |
| `OIDC_ADMIN_GROUP_NAME` | `mlflow-admin` | Groups with admin rights |
| `OIDC_USERS_DB_URI` | `sqlite:////data/auth.db` | Auth database (see above) |
| `DEFAULT_MLFLOW_PERMISSION` | `NO_PERMISSIONS` | Deny-by-default; grant access in the admin UI |
| `AUTOMATIC_LOGIN_REDIRECT` | `false` | Redirect unauthenticated browser requests to the IdP |
| `TRUSTED_PROXIES` | empty | **Required behind a reverse proxy**: CIDRs whose `X-Forwarded-*` headers are honoured |
| `MLFLOW_ALLOWED_HOSTS` | empty | Public DNS names must be listed (MLflow Host validation) |

## Programmatic access

- Interactive users create a **personal access token** in the MLflow UI
  (User profile → Tokens) or via
  `PATCH /api/2.0/mlflow/users/access-token`, then use it as the basic-auth
  password:

  ```bash
  export MLFLOW_TRACKING_URI=https://mlflow.example.com
  export MLFLOW_TRACKING_USERNAME=alice@example.com
  export MLFLOW_TRACKING_PASSWORD=mlf_...
  ```

- Automation should use short-lived **bearer tokens** (IdP client
  credentials) via `MLFLOW_TRACKING_TOKEN` instead of long-lived personal
  tokens. See the plugin's programmatic-access documentation.

## Demo stack with Keycloak

`docker-compose.oidc.yml` adds a Keycloak with a pre-imported realm and
points the server at it:

```bash
make up-oidc      # Keycloak on http://127.0.0.1:8180 (admin/admin)
make smoke-oidc   # end-to-end test, runs inside the compose network
make ci-smoke-oidc
```

Demo users (realm `mlflow`): `mlflow-user` / `mlflow-user-password` (group
`mlflow`), `mlflow-admin` / `mlflow-admin-password` (group `mlflow-admin`),
and `outsider` / `outsider-password` (no allowed group — login is refused).

Keycloak derives its issuer from the request host, so everything must use one
name end-to-end: inside the compose network the server and the smoke test use
`http://keycloak:8180`, and Keycloak itself listens on 8180 so that a host
browser sees the same port. To click through the UI from the host, map the
name once and browse the usual URL:

```bash
echo "127.0.0.1 keycloak" | sudo tee -a /etc/hosts
# then browse http://localhost:8080 → login redirects to http://keycloak:8180
```

The overlay whitelists the demo hostnames (`mlflow`, `localhost`,
`127.0.0.1`) for MLflow's Host validation and is not meant for production.

## Production checklist

- Set a strong, stable `SECRET_KEY` and keep the same value on every
  replica.
- Serve MLflow over HTTPS (reverse proxy) and set
  `SESSION_COOKIE_SECURE=true` (via a compose override; it forces the session
  cookie to HTTPS-only).
- Set `TRUSTED_PROXIES` to the proxy's CIDR range(s), otherwise the callback
  URL is built from the internal address and logins fail.
- List every public DNS name in `MLFLOW_ALLOWED_HOSTS` and every browser
  origin in `MLFLOW_CORS_ALLOWED_ORIGINS` if it calls the API directly.
- Use a shared database for `OIDC_USERS_DB_URI` when running more than one
  worker or replica (SQLite does not support that).
- Back up the auth database along with the MLflow database
  (see `docs/deployment.md`).
