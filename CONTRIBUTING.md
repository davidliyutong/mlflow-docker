# Contributing

## Setup

Prerequisites: Docker with Compose v2, GNU Make, and
[uv](https://docs.astral.sh/uv/) for the smoke test.

```bash
git clone https://github.com/davidliyutong/mlflow-docker.git
cd mlflow-docker
cp .env.example .env
make help
```

## Development loop

| Command | Purpose |
| --- | --- |
| `make lint` | Version pins, shellcheck, python syntax, compose config |
| `make build` | Build the image locally |
| `make up` / `make down` | Start / stop the Compose stack |
| `make logs` | Follow stack logs |
| `make smoke` | Smoke test against a running stack |
| `make ci-smoke` | Up + smoke + down, the same check CI runs |
| `make up-oidc` | Stack with the demo Keycloak (OIDC enabled) |
| `make smoke-oidc` / `make ci-smoke-oidc` | OIDC end-to-end test |
| `make dev` | Standalone server with sqlite + local artifacts |

## Conventions

- **Version pins**: the `Makefile` is the single source of truth for
  `VERSION` (MLflow), `PYTHON_VERSION` and `OIDC_AUTH_VERSION`
  (mlflow-oidc-auth; needs `mlflow>=3.16`). When bumping, update the pin
  there first, then propagate to the Dockerfile default, the compose
  fallbacks and the smoke test metadata; `make check-versions` must pass.
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:`, ...).
- **Shell**: `#!/usr/bin/env bash` with `set -euo pipefail`, shellcheck-clean.
- **Python**: scripts that run in the image live in `scripts/`; host-side test
  scripts use PEP 723 inline metadata and run through `uv`.
- **OIDC demo**: `docker-compose.oidc.yml` and `compose/keycloak/` are
  development fixtures; keep credentials out of anything production-facing.
- **Secrets**: never commit `.env` or credentials; compose defaults are for
  local development only.
- **Compose/config changes**: keep defaults backwards compatible; new knobs
  get a safe default and a row in `.env.example`.

## Pull requests

- Keep PRs focused; one concern per PR.
- CI (`CI` workflow) must be green: lint job + compose smoke job.
- Update documentation (`README.md`, `docs/`, `.env.example`) when behaviour,
  configuration or the workflow changes.
- Add an entry under `Unreleased` in `CHANGELOG.md` for user-visible changes.
