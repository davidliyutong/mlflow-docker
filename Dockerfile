FROM python:3.10-slim-bullseye
ARG VERSION
RUN pip install --no-cache mlflow==$VERSION && pip install mlflow[extras]
RUN pip install pymysql


WORKDIR /opt/mlflow
COPY entrypoint.sh /opt/mlflow/entrypoint.sh
RUN chmod +x /opt/mlflow/entrypoint.sh && mkdir -p /data

ENV MLFLOW_BACKEND_STORE_URI=file:///data/mlruns
ENV MLFLOW_ARTIFACT_ENDPOINT_URL=/data/artifacts

EXPOSE 5000
VOLUME [ "/data" ]
ENTRYPOINT ["/opt/mlflow/entrypoint.sh"]