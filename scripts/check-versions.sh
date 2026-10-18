#!/usr/bin/env bash
#
# Verify that version pins are in sync across the repository.
#
# The Makefile is the single source of truth. The same pins are duplicated in
# files that cannot read the Makefile (Dockerfile defaults, compose fallbacks,
# PEP 723 metadata in the smoke test); this script keeps them honest.
#
# Run directly or via `make check-versions`.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

trim() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

version="$(make --no-print-directory print-VERSION | trim)"
python_version="$(make --no-print-directory print-PYTHON_VERSION | trim)"
oidc_auth_version="$(make --no-print-directory print-OIDC_AUTH_VERSION | trim)"
keycloak_version="$(make --no-print-directory print-KEYCLOAK_VERSION | trim)"
python_minor="${python_version%.*}"

fail=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf 'ok: %s (%s)\n' "$name" "$expected"
    else
        printf 'MISMATCH: %s: expected "%s", found "%s"\n' "$name" "$expected" "$actual" >&2
        fail=1
    fi
}

dockerfile_version="$(grep -oE '^ARG VERSION=[0-9.]+' Dockerfile | head -n1 | cut -d= -f2 || true)"
dockerfile_python="$(grep -oE '^ARG PYTHON_VERSION=[0-9.]+' Dockerfile | head -n1 | cut -d= -f2 || true)"
dockerfile_oidc="$(grep -oE '^ARG OIDC_AUTH_VERSION=[0-9.]+' Dockerfile | head -n1 | cut -d= -f2 || true)"
check "Dockerfile ARG VERSION default" "$version" "$dockerfile_version"
check "Dockerfile ARG PYTHON_VERSION default" "$python_version" "$dockerfile_python"
check "Dockerfile ARG OIDC_AUTH_VERSION default" "$oidc_auth_version" "$dockerfile_oidc"

compose_version_raw="$(grep -oE 'MLFLOW_VERSION:-[0-9.]+' docker-compose.yml | head -n1 || true)"
compose_python_raw="$(grep -oE 'PYTHON_VERSION:-[0-9.]+' docker-compose.yml | head -n1 || true)"
compose_oidc_raw="$(grep -oE 'MLFLOW_OIDC_AUTH_VERSION:-[0-9.]+' docker-compose.yml | head -n1 || true)"
check "docker-compose.yml MLFLOW_VERSION fallback" "$version" "${compose_version_raw#MLFLOW_VERSION:-}"
check "docker-compose.yml PYTHON_VERSION fallback" "$python_version" "${compose_python_raw#PYTHON_VERSION:-}"
check "docker-compose.yml MLFLOW_OIDC_AUTH_VERSION fallback" "$oidc_auth_version" "${compose_oidc_raw#MLFLOW_OIDC_AUTH_VERSION:-}"

keycloak_version_raw="$(grep -oE 'KEYCLOAK_VERSION:-[0-9.]+' docker-compose.oidc.yml | head -n1 || true)"
check "docker-compose.oidc.yml KEYCLOAK_VERSION fallback" "$keycloak_version" "${keycloak_version_raw#KEYCLOAK_VERSION:-}"

smoke_version="$(grep -oE 'mlflow==[0-9]+\.[0-9]+\.[0-9]+' tests/smoke/mlflow_training_smoke.py | head -n1 | cut -d= -f3 || true)"
smoke_python="$(grep -oE 'requires-python = ">=[0-9]+\.[0-9]+' tests/smoke/mlflow_training_smoke.py | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
check "smoke test mlflow pin" "$version" "$smoke_version"
check "smoke test requires-python" "$python_minor" "$smoke_python"

if [[ $fail -ne 0 ]]; then
    printf 'Version pins are out of sync. Update Makefile (source of truth) and propagate the change.\n' >&2
    exit 1
fi

printf 'All version pins are in sync.\n'
