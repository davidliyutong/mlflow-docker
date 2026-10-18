# AGENTS.md

Docker image + Compose stack for an MLflow tracking server (MySQL metadata,
RustFS artifact storage, optional OIDC auth via the bundled mlflow-oidc-auth
plugin). This file describes the conventions agents must follow when changing
this repository.

## Golden rules

- The `Makefile` is the single source of truth for version pins (`VERSION`,
  `PYTHON_VERSION`, `OIDC_AUTH_VERSION`, `KEYCLOAK_VERSION`). Put them nowhere
  else without running `make check-versions`; never edit a pin in only one
  file.
- Run `make lint` after any change. Run `make ci-smoke` for changes touching
  the Dockerfile, `scripts/`, `docker-compose.yml` or the smoke test; also
  run `make ci-smoke-oidc` for anything touching OIDC, the overlay, the
  Keycloak realm or `entrypoint.sh`.
- Never commit `.env` or credentials. Compose defaults are dev-only.
- Conventional Commits for commit messages.
- Do not add comments to code unless they carry real information (why, not
  what).

## Layout

- `Dockerfile` — python base + pip install of mlflow/boto3/pymysql/cryptography.
- `scripts/entrypoint.sh` — resolves backend store (`MLFLOW_BACKEND_STORE_URI`
  or MySQL from `MYSQL_*`), artifact destination
  (`MLFLOW_ARTIFACTS_DESTINATION` or `s3://${MLFLOW_S3_BUCKET}/`), enables
  the `oidc-auth` app when `OIDC_DISCOVERY_URL` is set (waiting for discovery,
  dropping empty OIDC_* variables), then `exec mlflow server`.
- `scripts/ensure_bucket.py` — bucket bootstrap used by the `rustfs-init`
  compose service.
- `scripts/check-versions.sh` — `make check-versions`.
- `docker-compose.yml` — `db` (MySQL), `rustfs`, `rustfs-init`, `mlflow`.
  All knobs have safe defaults; new knobs must be documented in `.env.example`.
- `docker-compose.oidc.yml` — demo/test overlay: Keycloak (realm fixture in
  `compose/keycloak/`) and the `oidc-smoke` service, which runs the OIDC test
  inside the compose network so the issuer hostname matches everywhere.
- `tests/smoke/mlflow_training_smoke.py` — PEP 723 script (run via `uv run`).
- `tests/smoke/mlflow_oidc_smoke.py` — OIDC end-to-end test; runs inside the
  `oidc-smoke` container (plain `python`, the image already has mlflow).
- `.github/workflows/ci.yml` — lint + compose smoke + OIDC smoke on push/PR.
- `.github/workflows/release.yml` — verify (both smokes) + multi-arch publish
  to GHCR on GitHub Release or manual dispatch. Tags derive from `Makefile`
  pins.

## Common commands

```bash
make help            # target list
make check-versions  # version pins in sync
make lint            # shellcheck + py_compile + compose config
make up / down       # compose stack lifecycle
make smoke           # smoke test against running stack
make ci-smoke        # up + smoke + down
make up-oidc         # stack + demo Keycloak, OIDC enabled
make smoke-oidc      # OIDC end-to-end test (compose run, no uv needed)
make ci-smoke-oidc   # up-oidc + smoke-oidc + down
make dev             # standalone sqlite server for quick manual checks
```

## Style

- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`, quote expansions,
  shellcheck-clean; use `exec` for the final long-running process.
- Python: stdlib + boto3/mlflow only; no new runtime dependencies without a
  reason; host-side scripts use PEP 723 metadata pinned to `VERSION`.
- Docs: `README.md` is the entry point; runbooks live in `docs/`; user-visible
  changes get a `CHANGELOG.md` entry under `Unreleased`.
