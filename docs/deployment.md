# Deployment

The Compose stack runs four services: `db` (MySQL metadata), `rustfs`
(S3-compatible artifact storage), `rustfs-init` (one-shot bucket bootstrap)
and `mlflow` (tracking server with artifact serving).

## Single-host deployment

```bash
cp .env.example .env
# edit .env: credentials, MLFLOW_HOST_PORT, MLFLOW_ALLOWED_HOSTS
make up
```

The stack starts with `restart: unless-stopped`; it survives host reboots as
long as the Docker daemon does.

To run a published image instead of building from the checkout, set

```bash
MLFLOW_IMAGE=ghcr.io/davidliyutong/mlflow-docker:3.17.1
```

in `.env`. Pinning an explicit version (rather than `latest`) is recommended
for deployments.

To protect the server with SSO, set the `OIDC_*` variables (see
[docs/oidc.md](oidc.md)); no compose changes are required.

### Exposing the server

By default only the MLflow port is reachable from outside the host
(`MLFLOW_HOST_PORT`, default 8080). The RustFS API (9000) and console (9001)
bind to `127.0.0.1`; set `RUSTFS_BIND_HOST=0.0.0.0` only if external clients
must reach the object store directly (normally unnecessary, because artifacts
are proxied through the tracking server).

Behind a reverse proxy (Caddy example):

```
mlflow.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

When the server is reachable under a DNS name, MLflow's built-in Host
validation will reject requests unless you allow the host explicitly:

```bash
MLFLOW_ALLOWED_HOSTS=mlflow.example.com,mlflow.example.com:*
```

For browser-based clients on other origins, also set
`MLFLOW_CORS_ALLOWED_ORIGINS` (comma-separated, exact origins). Behind a
reverse proxy with OIDC enabled, also set `TRUSTED_PROXIES` (see
[docs/oidc.md](oidc.md)).

### Production checklist

- Change `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `MLFLOW_S3_SECRET_KEY` in
  `.env` before first start (volumes are initialized with these values).
- Leave `MLFLOW_ALLOWED_HOSTS` empty only if clients use localhost/private
  IPs; set it for every public DNS name.
- Terminate TLS at a reverse proxy and keep the MLflow port on loopback with
  `MLFLOW_HOST_PORT=127.0.0.1:8080` (Compose accepts a full bind spec here).
- Keep `RUSTFS_BIND_HOST=127.0.0.1` unless you have a specific need.
- Back up both volumes (see below) before upgrades.

## Upgrades

1. Back up the database and artifacts (below).
2. Update the image: bump `VERSION` in the `Makefile` (source of truth), or
   point `MLFLOW_IMAGE` at the new published tag.
3. `make up` — MLflow applies its schema migrations on startup.

MySQL major upgrades (e.g. 5.7 → 8.0) are **not** in-place: dump the data
first and restore into a fresh `db_data` volume.

## Backups

Metadata (MySQL):

```bash
docker compose exec db sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' > mlflow-db.sql
```

Artifacts (RustFS volume):

```bash
docker run --rm -v mlflow-docker_rustfs_data:/data -v "$PWD:/backup" \
  alpine tar czf /backup/rustfs-data.tar.gz -C /data .
```

Replace the volume name with your Compose project prefix (`docker volume ls`)
if it differs.

## Health and observability

- The image defines a `HEALTHCHECK` against `GET /health`; check it with
  `docker inspect --format '{{.State.Health.Status}}' <container>`.
- `make logs` follows all services; logs go to the Docker logging driver.
- The MLflow container prints the resolved backend URI (password masked) and
  artifact destination on startup.

## Artifact downloads with MLflow >= 3.13

The server advertises presigned-download support, so MLflow clients download
artifacts **directly from the S3 endpoint** (bypassing the tracking server)
whenever `MLFLOW_S3_ENDPOINT_URL` is reachable to them. The URL is minted from
the server's own configuration, so with the default
`http://rustfs:9000` (an internal compose name) clients outside the compose
network cannot use it.

Choose one:

- Make the S3 endpoint reachable from clients (set `RUSTFS_BIND_HOST=0.0.0.0`
  or use an external S3) — best performance; or
- run clients inside the compose network; or
- opt out on the client side with `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false`,
  which restores proxied downloads through the tracking server (this is what
  `make smoke` does from the host).

## External services

- **External MySQL**: set `MLFLOW_BACKEND_STORE_URI` in `.env`; the entrypoint
  skips the bundled-DB wait when it is set.
- **External S3 (AWS, MinIO, ...)**: point `MLFLOW_S3_ENDPOINT_URL`,
  `MLFLOW_S3_BUCKET`, `MLFLOW_S3_ACCESS_KEY`, `MLFLOW_S3_SECRET_KEY` at the
  target. The `rustfs` service can then be removed from the stack.
- **Identity provider (OIDC)**: see [docs/oidc.md](oidc.md).
