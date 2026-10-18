# MLflow Tracking Server Docker Image

[![CI](https://github.com/davidliyutong/mlflow-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/davidliyutong/mlflow-docker/actions/workflows/ci.yml)

Docker image and Compose stack for an [MLflow](https://mlflow.org) tracking
server backed by:

- **MySQL** for metadata (experiments, runs, params, metrics)
- **RustFS** (S3-compatible) for artifacts
- optional **OIDC authentication** via
  [mlflow-oidc-auth](https://github.com/mlflow-oidc/mlflow-oidc-auth)
  (SSO login, personal access tokens, per-user/group permissions)

The server runs with `--serve-artifacts`, so clients only need the tracking
URI; artifact upload and download are proxied through the server.

## Quickstart

Prerequisites: Docker with Compose v2 and GNU Make.

```bash
cp .env.example .env      # review ports and credentials
make up                   # build the image and start db + rustfs + mlflow
```

- MLflow UI/API: <http://localhost:8080>
- RustFS console: <http://127.0.0.1:9001> (credentials from `.env`)

Point your training code at the server:

```python
import mlflow

mlflow.set_tracking_uri("http://localhost:8080")
```

Stop the stack with `make down`; `make logs` follows the logs.

To put the server behind SSO instead, set the `OIDC_*` variables in `.env`
(or try the bundled demo: `make up-oidc`); see
[docs/oidc.md](docs/oidc.md).

## Smoke test

The smoke test trains a tiny linear regression, logs params, metrics and five
artifact types (JSON, binary, PNG, text, JSONL), then downloads and verifies
every artifact through the tracking server.

```bash
make smoke        # against a running stack (needs uv)
make ci-smoke     # up + smoke + down in one shot
make smoke-oidc   # OIDC end-to-end test against the demo IdP (no uv needed)
make ci-smoke-oidc
```

The OIDC smoke test signs in through the bundled Keycloak (authorization
code + PKCE), mints a personal access token and repeats the full training
smoke as an authenticated client, then checks admin and group restrictions.

## Configuration

Copy `.env.example` to `.env` and adjust. The main knobs:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MLFLOW_HOST_PORT` | `8080` | Host port of the MLflow UI/API |
| `MLFLOW_ALLOWED_HOSTS` | empty | Exact `Host` patterns; empty keeps MLflow's built-in validation (localhost + private IPs). Required for public DNS names |
| `MLFLOW_CORS_ALLOWED_ORIGINS` | empty | Browser origins allowed to call the API cross-origin |
| `MLFLOW_IMAGE` | `ghcr.io/davidliyutong/mlflow-docker:latest` | Pin a published image instead of building locally |
| `MLFLOW_BACKEND_STORE_URI` | empty | Use an external database instead of the bundled MySQL |
| `MLFLOW_WORKERS` | MLflow default (4) | Server workers; use `1` with the default SQLite auth DB |
| `MYSQL_*`, `MLFLOW_S3_*` | dev values | Database and RustFS credentials; change for anything but local dev |
| `RUSTFS_BIND_HOST` | `127.0.0.1` | Bind host for the RustFS API (9000) and console (9001) |
| `OIDC_*`, `SECRET_KEY` | empty | OIDC authentication; setting `OIDC_DISCOVERY_URL` enables it — see [docs/oidc.md](docs/oidc.md) |

Build-time version pins (`VERSION`, `PYTHON_VERSION`, `OIDC_AUTH_VERSION`)
live in the `Makefile`; `make check-versions` verifies they stay in sync with
the Dockerfile, Compose files and smoke tests.

See [docs/deployment.md](docs/deployment.md) for production guidance
(reverse proxy, TLS, backups, upgrades),
[docs/oidc.md](docs/oidc.md) for authentication, and
[docs/release.md](docs/release.md) for the release process.

## Development

Prerequisites: Docker, GNU Make, `uv` (for the smoke test).

```bash
make help            # list all targets
make check-versions  # verify version pins are in sync
make lint            # shellcheck + python + compose config checks
make build           # build the image
make dev             # standalone server: sqlite + local artifacts, port 8080
make up / down       # start / stop the compose stack
make up-oidc         # compose stack + demo Keycloak (OIDC enabled)
make ci-smoke        # full end-to-end check
make ci-smoke-oidc   # end-to-end check of the OIDC path
```

Repository layout:

```
├── Dockerfile               # image definition (pins base python, mlflow, oidc plugin)
├── docker-compose.yml       # db + rustfs + rustfs-init + mlflow services
├── docker-compose.oidc.yml  # OIDC demo overlay: Keycloak + smoke test service
├── compose/keycloak/        # demo realm (users, groups, client)
├── Makefile                 # single entrypoint; source of truth for version pins
├── scripts/
│   ├── entrypoint.sh        # resolves backend store / artifact destination / OIDC, execs mlflow
│   ├── ensure_bucket.py     # creates the artifact bucket before the server starts
│   └── check-versions.sh    # version pin consistency check
├── tests/smoke/             # PEP 723 training smoke + OIDC end-to-end smoke
├── docs/                    # deployment, OIDC and release runbooks
└── .github/workflows/       # CI (lint + smoke + oidc smoke) and Release (GHCR, multi-arch)
```

Contribution workflow and conventions: [CONTRIBUTING.md](CONTRIBUTING.md).

## References

- MLflow Tracking Quickstart: <https://mlflow.org/docs/latest/ml/getting-started/quickstart/>
- Official MLflow Docker image: <https://ghcr.io/mlflow/mlflow>
