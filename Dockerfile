ARG PYTHON_VERSION=3.12.13
FROM python:${PYTHON_VERSION}-slim-bookworm
ARG VERSION=3.12.0
RUN pip install --no-cache-dir "setuptools<81" "mlflow==${VERSION}" boto3 pymysql


WORKDIR /opt/mlflow
COPY entrypoint.sh /opt/mlflow/entrypoint.sh
RUN chmod +x /opt/mlflow/entrypoint.sh && mkdir -p /data

ENV MLFLOW_BACKEND_STORE_URI=file:///data/mlruns
ENV MLFLOW_ARTIFACT_ENDPOINT_URL=/data/artifacts

EXPOSE 8080
VOLUME [ "/data" ]
ENTRYPOINT ["/opt/mlflow/entrypoint.sh"]
