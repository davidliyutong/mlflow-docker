#!/bin/bash

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
echo "MYSQL_USER=" $MYSQL_USER # mlflow
echo "MYSQL_PASSWORD=" $MYSQL_PASSWORD # mlflow
echo "MYSQL_HOST=" $MYSQL_HOST # mysql
echo "MYSQL_PORT=" $MYSQL_PORT # 3306
echo "MYSQL_DATABASE=" $MYSQL_DATABASE # mlflowdb
MLFLOW_BACKEND_STORE_URI="mysql+pymysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
echo "MLFLOW_BACKEND_STORE_URI=" $MLFLOW_BACKEND_STORE_URI # postgresql://user:password@postgres:5432/mlflowdb
# echo "MLFLOW_ARTIFACT_ENDPOINT_URL=" $MLFLOW_ARTIFACT_ENDPOINT_URL

echo "MLFLOW_S3_ENDPOINT_URL=" $MLFLOW_S3_ENDPOINT_URL # http://minio:9000
echo "MLFLOW_S3_IGNORE_TLS=" $MLFLOW_S3_IGNORE_TLS # true
echo "MLFLOW_S3_BUCKET=" $MLFLOW_S3_BUCKET # mlflow
echo "AWS_ACCESS_KEY_ID=" $AWS_ACCESS_KEY_ID # minio
echo "AWS_SECRET_ACCESS_KEY=" $AWS_SECRET_ACCESS_KEY
echo "AWS_DEFAULT_REGION=" $AWS_DEFAULT_REGION # us-east-1

mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri ${MLFLOW_BACKEND_STORE_URI}\
    --artifacts-destination s3://${MLFLOW_S3_BUCKET}/ \
    --default-artifact-root s3://${MLFLOW_S3_BUCKET}/