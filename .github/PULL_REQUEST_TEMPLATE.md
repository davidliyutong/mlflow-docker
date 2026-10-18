## Summary

<!-- What changed and why. Link related issues. -->

## Checklist

- [ ] `make lint` passes (includes `make check-versions`)
- [ ] `make ci-smoke` passes for changes to the Dockerfile, `scripts/`,
      `docker-compose.yml` or the smoke test
- [ ] `make ci-smoke-oidc` passes for changes to OIDC, the overlay, the
      Keycloak realm or `entrypoint.sh`
- [ ] Documentation updated (`README.md`, `docs/`, `.env.example`) for
      behaviour or configuration changes
- [ ] `CHANGELOG.md` entry added under `Unreleased` for user-visible changes
