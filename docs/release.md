# Release process

## Versioning

- The image is a wrapper around MLflow: `VERSION` in the `Makefile` is the
  bundled MLflow version and the primary image tag. `PYTHON_VERSION` (base
  image) and `OIDC_AUTH_VERSION` (mlflow-oidc-auth plugin) are pinned the same
  way and must satisfy MLflow's requirements (`mlflow-oidc-auth` needs
  `mlflow>=3.16`).
- GitHub Releases are tagged `v<version>` (e.g. `v3.17.1`). Hotfix rebuilds
  of the same upstream version use a suffix (e.g. `3.17.1-hotfix1`).
- On a release, the workflow pushes: `<release tag>`, `<VERSION>` and
  `latest`; a manual dispatch pushes exactly the requested tag.
- `latest` always points at the most recent published release.

## What the workflow does

`.github/workflows/release.yml` runs three jobs:

1. **verify** — builds the stack with Compose and runs the full smoke test
   (`make ci-smoke` equivalent). A failing smoke test blocks publishing.
2. **verify-oidc** — runs the OIDC end-to-end test (`make ci-smoke-oidc`
   equivalent) against the bundled Keycloak.
3. **publish** — multi-arch build (`linux/amd64`, `linux/arm64`) with the
   version pins read from the `Makefile`, pushed to GHCR with GHA layer
   caching.

## Cutting a release

1. Ensure `main` is green (CI workflow) and the smoke tests pass locally
   (`make ci-smoke`, `make ci-smoke-oidc`).
2. Update `CHANGELOG.md`: move `Unreleased` entries under the new version.
3. If the bundled MLflow, Python or plugin version changed, bump the pin in
   the `Makefile` and run `make check-versions`; commit the propagated
   changes.
4. Tag and create a GitHub Release:

   ```bash
   git tag v3.17.1
   git push origin v3.17.1
   gh release create v3.17.1 --title v3.17.1 --notes-from-tag
   ```

   Publishing the release triggers the workflow.
5. Verify the published image:

   ```bash
   docker run --rm ghcr.io/davidliyutong/mlflow-docker:3.17.1 \
     python -c "import mlflow, mlflow_oidc_auth; print(mlflow.__version__)"
   ```

## Manual publish

For a rebuild without a new release (e.g. base image security update):

```bash
gh workflow run release.yml -f image_tag=3.17.1-hotfix1
```

## Rollback

Deployments pin an image tag, so rolling back means pinning the previous tag:
set `MLFLOW_IMAGE=ghcr.io/davidliyutong/mlflow-docker:<previous>` in `.env`
and `make up`. Database migrations are forward-only; restore the pre-upgrade
database backup if the schema changed (`docs/deployment.md`).
