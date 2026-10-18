# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Image tags follow the bundled MLflow version (`VERSION` in the `Makefile`),
with GitHub Releases named `v<version>`; see `docs/release.md`.

## [Unreleased]

### Added

- CI workflow (`ci.yml`): version-pin check, lint, and a Compose smoke test on
  push to `main` and on pull requests.
- Release workflow (`release.yml`): re-runs the smoke test, then publishes
  multi-arch images (`linux/amd64`, `linux/arm64`) to GHCR on GitHub Release
  or manual dispatch. Replaces `ghcr-publish.yml`.
- `scripts/check-versions.sh` and `make check-versions` to keep version pins
  in sync across Makefile, Dockerfile, Compose and the smoke test.
- Container `HEALTHCHECK` against the MLflow `/health` endpoint.
- **OIDC authentication** via the bundled
  [mlflow-oidc-auth](https://github.com/mlflow-oidc/mlflow-oidc-auth) plugin
  (`OIDC_AUTH_VERSION`, default 11.0.0). Setting `OIDC_DISCOVERY_URL` enables
  SSO login, personal access tokens and per-user/group permissions; see
  `docs/oidc.md`.
- OIDC demo/test overlay (`docker-compose.oidc.yml`) with a bundled Keycloak
  and pre-imported realm (`compose/keycloak/`), plus `make up-oidc`,
  `make smoke-oidc` and `make ci-smoke-oidc`.
- OIDC end-to-end smoke test (`tests/smoke/mlflow_oidc_smoke.py`): PKCE login,
  personal-access-token creation, full authenticated training run, admin and
  group-restriction checks. Runs inside the compose network so the OIDC issuer
  is consistent. Added to CI and to the release verification jobs.
- `CONTRIBUTING.md`, `AGENTS.md`, `docs/deployment.md`, `docs/oidc.md`,
  `docs/release.md`, `.editorconfig`, `.dockerignore`, PR template.

### Changed

- Layout: `entrypoint.sh` moved to `scripts/`; the inline RustFS bucket
  bootstrap moved from `docker-compose.yml` to `scripts/ensure_bucket.py`.
- Bundled MLflow 3.12.0 → 3.17.1 (mlflow-oidc-auth requires >= 3.16).
- Compose: OIDC variables are forwarded to the `mlflow` service and `/data`
  is now a named volume (`mlflow_data`), used for the default SQLite auth
  database; `MLFLOW_WORKERS` is exposed.
- Entrypoint: enables `--app-name oidc-auth` when `OIDC_DISCOVERY_URL` is set,
  waits for the OIDC discovery document, drops empty `OIDC_*`/`SECRET_KEY`
  variables (compose forwards unset knobs as empty strings, which the plugin
  reads as explicit configuration), and defaults `OIDC_USERS_DB_URI` to
  `sqlite:////data/auth.db`.
- Upgrade note: with MLflow >= 3.13 clients download artifacts via presigned
  S3 URLs when the endpoint is reachable, bypassing the tracking server. With
  the internal `rustfs:9000` endpoint, external clients should either reach
  the S3 service or set `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false`
  (`make smoke` does the latter from the host); see `docs/deployment.md`.
- `Makefile` is now the single entrypoint: `make help`, `up`/`down`/`logs`,
  `lint`, `ci-smoke`, `clean`; `compose-up`/`compose-down` kept as aliases.
- Compose: credentials, image references, ports and regions are now
  parameterized via `.env` (documented in `.env.example`).
- RustFS API (9000) and console (9001) now bind to `127.0.0.1` by default;
  set `RUSTFS_BIND_HOST=0.0.0.0` to expose them.
- `.env.example` no longer suggests `MLFLOW_ALLOWED_HOSTS=*`; empty keeps
  MLflow's built-in host validation.
- Entrypoint: `MLFLOW_BACKEND_STORE_URI` is now honoured when set (external
  databases), `MLFLOW_ARTIFACTS_DESTINATION` overrides the S3 destination,
  the dead sqlite branch was removed, and the server is started with `exec`.
- `make dev` now runs a working standalone server (sqlite + local artifacts).
- Dockerfile: added image labels and the `cryptography` package (needed for
  MySQL 8 `caching_sha2_password` authentication via pymysql).
- README restructured; deployment and release runbooks moved to `docs/`.

### Removed

- Misleading default `ENV MLFLOW_BACKEND_STORE_URI` / `MLFLOW_ARTIFACT_ENDPOINT_URL`
  from the Dockerfile (the entrypoint always built a MySQL URI anyway).

## [3.12.0] - 2026-05-10

### Added

- RustFS (S3-compatible) artifact storage with a `rustfs-init` bucket
  bootstrap service.
- MySQL readiness wait in the entrypoint.
- `--allowed-hosts` / `--cors-allowed-origins` pass-through
  (`MLFLOW_ALLOWED_HOSTS`, `MLFLOW_CORS_ALLOWED_ORIGINS`).
- `.env.example`, GHCR publish workflow.

### Changed

- Python base image 3.12.13, MLflow 3.12.0.
- Smoke test covers metrics plus five artifact types with download
  verification.

## [1.0.0] - 2024-06-20

### Added

- Initial Docker image and Compose stack (MLflow + MySQL + MinIO).
