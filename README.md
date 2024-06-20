# Self-Host MLflow Docker Image

This repository contians a modified docker image of [mlflow](https://github.com/mlflow/mlflow) that works with external MySQL database and Object Storage (e.g. MinIO).

## How to build

### Prereqisites

- Docker Installation
- GNU Make

### Instructions

Adjust the `Makefile` to meet your need:

```makefile
PERSISTENCE_DIR = $(shell pwd)/data
VERSION = 2.14.0
NAMESPACE = davidliyutong
IMAGE = mlflow
```

> In the example above, the image will be built with tag `davidliyutong/mlflow:2.14.0`

Execute `make build` to build images

```shell
make build
```

Execute `make push` to push images to registry.

```shell
make push
```

## How to run

### Local Setup with docker-compose

Install docker-compose:

```shell
pip install docker-compose
```

Modify the `docker-compose.yaml` to meet your need:

```yaml
version: "3"
services:
  db:
    image: mysql:5.7
    restart: unless-stopped
    container_name: db
    expose:
      - "3306"
    volumes:
      - db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: mlflow
      MYSQL_DATABASE: mlflowdb
      MYSQL_USER: mlflow
      MYSQL_PASSWORD: mlflow
  mlflow:
    image: davidliyutong/mlflow:latest
    restart: unless-stopped
    container_name: mlflow
    ports:
      - "5000:5000"
    environment:
      MYSQL_DATABASE: mlflowdb
      MYSQL_USER: mlflow
      MYSQL_PASSWORD: mlflow
      MYSQL_HOST: db
      MYSQL_PORT: 3306
      MLFLOW_S3_ENDPOINT_URL: http://oss.example.com:9000
      MLFLOW_S3_IGNORE_TLS: "true"
      MLFLOW_S3_BUCKET: mlflow
      AWS_ACCESS_KEY_ID: <your access key>
      AWS_SECRET_ACCESS_KEY: <your secret key>
volumes:
  db_data:
```

> The provided access key should have write access to `MLFLOW_S3_BUCKET`

## Reference

- [Official Docker Image](https://ghcr.io/mlflow/mlflow)
- [Bitnami's MLflow Image](https://hub.docker.com/r/bitnami/mlflow)
