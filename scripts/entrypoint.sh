#!/usr/bin/env bash
#
# Entrypoint for the MLflow tracking server image.
#
# Backend store:
#   1. MLFLOW_BACKEND_STORE_URI is used as-is when set.
#   2. Otherwise a MySQL URI is built from MYSQL_* variables (after waiting
#      for MySQL to accept connections).
#
# Artifact storage:
#   - MLFLOW_ARTIFACTS_DESTINATION when set (e.g. /data/artifacts or s3://bucket/)
#   - otherwise s3://${MLFLOW_S3_BUCKET:-mlflow}/
#
# Server bind address: MLFLOW_HOST (default 0.0.0.0), MLFLOW_PORT (default 8080).
# MLFLOW_ALLOWED_HOSTS and MLFLOW_CORS_ALLOWED_ORIGINS are forwarded when set.

set -euo pipefail

if [[ -n "${MLFLOW_BACKEND_STORE_URI:-}" ]]; then
    backend_store_uri="${MLFLOW_BACKEND_STORE_URI}"
    echo "Using MLFLOW_BACKEND_STORE_URI=${backend_store_uri}"
else
    MYSQL_HOST="${MYSQL_HOST:-db}"
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    MYSQL_DATABASE="${MYSQL_DATABASE:-mlflowdb}"
    MYSQL_USER="${MYSQL_USER:-mlflow}"
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-mlflow}"
    export MYSQL_HOST MYSQL_PORT MYSQL_DATABASE MYSQL_USER MYSQL_PASSWORD

    python - <<'PY'
import os
import time

import pymysql

deadline = time.time() + int(os.environ.get("MYSQL_WAIT_TIMEOUT", "60"))
last_error = None

while time.time() < deadline:
    try:
        connection = pymysql.connect(
            host=os.environ["MYSQL_HOST"],
            port=int(os.environ["MYSQL_PORT"]),
            user=os.environ["MYSQL_USER"],
            password=os.environ["MYSQL_PASSWORD"],
            database=os.environ["MYSQL_DATABASE"],
            connect_timeout=3,
        )
        connection.close()
        break
    except Exception as exc:
        last_error = exc
        print(f"Waiting for MySQL at {os.environ['MYSQL_HOST']}:{os.environ['MYSQL_PORT']}: {exc}")
        time.sleep(2)
else:
    raise SystemExit(f"MySQL was not ready before timeout: {last_error}")
PY

    backend_store_uri="mysql+pymysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
    echo "Using MySQL backend: mysql+pymysql://${MYSQL_USER}:***@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
fi

# Compose forwards unset knobs as empty strings, which the plugin reads as
# explicit configuration (disabling its built-in defaults). Drop them first.
for var in OIDC_DISCOVERY_URL OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_REDIRECT_URI \
    OIDC_SCOPE OIDC_PROVIDER_DISPLAY_NAME OIDC_USERNAME_FIELD OIDC_GROUP_NAME \
    OIDC_GROUP_NAME_PATTERN OIDC_ADMIN_GROUP_NAME OIDC_PUBLIC_CLIENT \
    OIDC_USERS_DB_URI DEFAULT_MLFLOW_PERMISSION AUTOMATIC_LOGIN_REDIRECT \
    SECRET_KEY TRUSTED_PROXIES MLFLOW_WORKERS; do
    if [[ -z "${!var:-}" ]]; then
        unset "$var"
    fi
done

# OIDC authentication: enabled when OIDC_DISCOVERY_URL (or MLFLOW_APP_NAME) is
# set; the bundled mlflow-oidc-auth plugin app is then used as the server app.
MLFLOW_APP_NAME="${MLFLOW_APP_NAME:-}"
if [[ -z "$MLFLOW_APP_NAME" && -n "${OIDC_DISCOVERY_URL:-}" ]]; then
    MLFLOW_APP_NAME="oidc-auth"
fi

if [[ -n "$MLFLOW_APP_NAME" ]]; then
    OIDC_WAIT_TIMEOUT="${OIDC_WAIT_TIMEOUT:-60}"
    if [[ -n "${OIDC_DISCOVERY_URL:-}" && "$MLFLOW_APP_NAME" == "oidc-auth" ]]; then
        OIDC_DISCOVERY_URL="$OIDC_DISCOVERY_URL" OIDC_WAIT_TIMEOUT="$OIDC_WAIT_TIMEOUT" python - <<'PY'
import os
import time
import urllib.request

url = os.environ["OIDC_DISCOVERY_URL"]
deadline = time.time() + int(os.environ["OIDC_WAIT_TIMEOUT"])
last_error = None

while time.time() < deadline:
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            if response.status == 200:
                break
    except Exception as exc:
        last_error = exc
        print(f"Waiting for OIDC discovery at {url}: {exc}")
    time.sleep(2)
else:
    raise SystemExit(f"OIDC discovery was not ready before timeout: {last_error}")
PY
    fi
    export OIDC_USERS_DB_URI="${OIDC_USERS_DB_URI:-sqlite:////data/auth.db}"
    if [[ -z "${SECRET_KEY:-}" ]]; then
        echo "WARNING: SECRET_KEY is not set; sessions will not survive restarts"
    fi
fi

MLFLOW_HOST="${MLFLOW_HOST:-0.0.0.0}"
MLFLOW_PORT="${MLFLOW_PORT:-8080}"
MLFLOW_S3_ENDPOINT_URL="${MLFLOW_S3_ENDPOINT_URL:-http://rustfs:9000}"
MLFLOW_S3_IGNORE_TLS="${MLFLOW_S3_IGNORE_TLS:-true}"
MLFLOW_S3_BUCKET="${MLFLOW_S3_BUCKET:-mlflow}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export MLFLOW_S3_ENDPOINT_URL MLFLOW_S3_IGNORE_TLS MLFLOW_S3_BUCKET AWS_DEFAULT_REGION

artifacts_destination="${MLFLOW_ARTIFACTS_DESTINATION:-s3://${MLFLOW_S3_BUCKET}/}"
MLFLOW_ALLOWED_HOSTS="${MLFLOW_ALLOWED_HOSTS:-${MLFLOW_SERVER_ALLOWED_HOSTS:-}}"
MLFLOW_CORS_ALLOWED_ORIGINS="${MLFLOW_CORS_ALLOWED_ORIGINS:-${MLFLOW_SERVER_CORS_ALLOWED_ORIGINS:-}}"

echo "MLFLOW_HOST=$MLFLOW_HOST"
echo "MLFLOW_PORT=$MLFLOW_PORT"
echo "MLFLOW_S3_ENDPOINT_URL=$MLFLOW_S3_ENDPOINT_URL"
echo "MLFLOW_S3_IGNORE_TLS=$MLFLOW_S3_IGNORE_TLS"
echo "MLFLOW_S3_BUCKET=$MLFLOW_S3_BUCKET"
echo "MLFLOW_ARTIFACTS_DESTINATION=$artifacts_destination"
echo "MLFLOW_ALLOWED_HOSTS=$MLFLOW_ALLOWED_HOSTS"
echo "MLFLOW_CORS_ALLOWED_ORIGINS=$MLFLOW_CORS_ALLOWED_ORIGINS"
echo "MLFLOW_APP_NAME=$MLFLOW_APP_NAME"
if [[ -n "$MLFLOW_APP_NAME" ]]; then
    echo "OIDC_DISCOVERY_URL=${OIDC_DISCOVERY_URL:-}"
    echo "OIDC_CLIENT_ID=${OIDC_CLIENT_ID:-}"
    echo "OIDC_USERS_DB_URI=$OIDC_USERS_DB_URI"
fi
echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}"
echo "AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"

mlflow_server_args=(
    server
    --host "$MLFLOW_HOST"
    --port "$MLFLOW_PORT"
    --backend-store-uri "$backend_store_uri"
    --serve-artifacts
    --artifacts-destination "$artifacts_destination"
)

if [[ -n "$MLFLOW_ALLOWED_HOSTS" ]]; then
    mlflow_server_args+=(--allowed-hosts "$MLFLOW_ALLOWED_HOSTS")
fi

if [[ -n "$MLFLOW_CORS_ALLOWED_ORIGINS" ]]; then
    mlflow_server_args+=(--cors-allowed-origins "$MLFLOW_CORS_ALLOWED_ORIGINS")
fi

if [[ -n "$MLFLOW_APP_NAME" ]]; then
    mlflow_server_args+=(--app-name "$MLFLOW_APP_NAME")
fi

exec mlflow "${mlflow_server_args[@]}"
