#!/bin/bash
# export MLFLOW_S3_ENDPOINT_URL=http://minio:9000
# export MLFLOW_BACKEND_STORE_URI=postgresql://user:password@postgres:5432/mlflowdb
export MLFLOW_S3_BUCKET=mlflow
export MLFLOW_S3_IGNORE_TLS=true

if [[ $MLFLOW_BACKEND_STORE_URI  == "sqlite://"* ]]; then
    path=${MLFLOW_BACKEND_STORE_URI#*sqlite:\/\/}
    if [[ -f $path ]]; then
        echo "Found sqlite database at $path"
        exit 0
    else
        echo "Creating sqlite database at $path"
        touch path
    fi
fi


echo "Starting mlflow server"
echo "MLFLOW_BACKEND_STORE_URI=" $MLFLOW_BACKEND_STORE_URI 
echo "MLFLOW_ARTIFACT_ENDPOINT_URL=" $MLFLOW_ARTIFACT_ENDPOINT_URL
mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri $MLFLOW_BACKEND_STORE_URI \
    --default-artifact-root $MLFLOW_ARTIFACT_ENDPOINT_URL
    # --default-artifact-root ${MLFLOW_S3_ENDPOINT_URL}/${MLFLOW_S3_BUCKET}root@unifold-mlflow-bc454886b-d9bfb:/opt/mlflow# 