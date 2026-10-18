ARG PYTHON_VERSION=3.12.13
FROM python:${PYTHON_VERSION}-slim-bookworm

ARG VERSION=3.17.1
ARG OIDC_AUTH_VERSION=11.0.0

LABEL org.opencontainers.image.title="MLflow Tracking Server" \
      org.opencontainers.image.description="MLflow tracking server with MySQL metadata store, S3-compatible artifact storage and optional OIDC authentication" \
      org.opencontainers.image.source="https://github.com/davidliyutong/mlflow-docker" \
      org.opencontainers.image.version="${VERSION}"

RUN pip install --no-cache-dir \
    "setuptools<81" \
    "mlflow==${VERSION}" \
    "mlflow-oidc-auth==${OIDC_AUTH_VERSION}" \
    boto3 \
    pymysql \
    cryptography

WORKDIR /opt/mlflow
COPY scripts/entrypoint.sh /opt/mlflow/entrypoint.sh
COPY scripts/ensure_bucket.py /opt/mlflow/ensure_bucket.py
RUN chmod +x /opt/mlflow/entrypoint.sh /opt/mlflow/ensure_bucket.py && mkdir -p /data

ENV MLFLOW_ALLOWED_HOSTS=""
ENV MLFLOW_CORS_ALLOWED_ORIGINS=""

EXPOSE 8080
VOLUME [ "/data" ]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4).status == 200 else 1)"

ENTRYPOINT ["/opt/mlflow/entrypoint.sh"]
