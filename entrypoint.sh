#!/bin/bash

set -euo pipefail

if [[ ${MLFLOW_BACKEND_STORE_URI:-} == "sqlite://"* ]]; then
    path=${MLFLOW_BACKEND_STORE_URI#*sqlite:\/\/}
    if [[ -f $path ]]; then
        echo "Found sqlite database at $path"
        exit 0
    else
        echo "Creating sqlite database at $path"
        touch "$path"
    fi
fi

export MYSQL_HOST="${MYSQL_HOST:-db}"
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-mlflowdb}"
export MYSQL_USER="${MYSQL_USER:-mlflow}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-mlflow}"
export MLFLOW_S3_ENDPOINT_URL="${MLFLOW_S3_ENDPOINT_URL:-http://rustfs:9000}"
export MLFLOW_S3_IGNORE_TLS="${MLFLOW_S3_IGNORE_TLS:-true}"
export MLFLOW_S3_BUCKET="${MLFLOW_S3_BUCKET:-mlflow}"
export MLFLOW_ALLOWED_HOSTS="${MLFLOW_ALLOWED_HOSTS:-${MLFLOW_SERVER_ALLOWED_HOSTS:-}}"
export MLFLOW_CORS_ALLOWED_ORIGINS="${MLFLOW_CORS_ALLOWED_ORIGINS:-${MLFLOW_SERVER_CORS_ALLOWED_ORIGINS:-}}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

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

echo "Starting mlflow server"
echo "MYSQL_USER=$MYSQL_USER"
echo "MYSQL_HOST=$MYSQL_HOST"
echo "MYSQL_PORT=$MYSQL_PORT"
echo "MYSQL_DATABASE=$MYSQL_DATABASE"
MLFLOW_BACKEND_STORE_URI="mysql+pymysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
echo "MLFLOW_BACKEND_STORE_URI=mysql+pymysql://${MYSQL_USER}:***@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"

echo "MLFLOW_S3_ENDPOINT_URL=$MLFLOW_S3_ENDPOINT_URL"
echo "MLFLOW_S3_IGNORE_TLS=$MLFLOW_S3_IGNORE_TLS"
echo "MLFLOW_S3_BUCKET=$MLFLOW_S3_BUCKET"
echo "MLFLOW_ALLOWED_HOSTS=$MLFLOW_ALLOWED_HOSTS"
echo "MLFLOW_CORS_ALLOWED_ORIGINS=$MLFLOW_CORS_ALLOWED_ORIGINS"
echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}"
echo "AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"

mlflow_server_args=(
    server
    --host 0.0.0.0
    --port 8080
    --backend-store-uri "${MLFLOW_BACKEND_STORE_URI}"
    --serve-artifacts
    --artifacts-destination "s3://${MLFLOW_S3_BUCKET}/"
)

if [[ -n $MLFLOW_ALLOWED_HOSTS ]]; then
    mlflow_server_args+=(--allowed-hosts "$MLFLOW_ALLOWED_HOSTS")
fi

if [[ -n $MLFLOW_CORS_ALLOWED_ORIGINS ]]; then
    mlflow_server_args+=(--cors-allowed-origins "$MLFLOW_CORS_ALLOWED_ORIGINS")
fi

mlflow "${mlflow_server_args[@]}"
