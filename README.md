# MLflow Tracking Server Docker Image

This repository provides a Docker image for running an MLflow Tracking Server backed by:

- **MySQL** for metadata (runs, params, metrics)
- **S3-compatible object storage** (such as MinIO) for artifacts

It is updated to align with the latest MLflow quickstart workflow (`mlflow server --host 127.0.0.1 --port 8080`) from MLflow docs.

## Build

### Prerequisites

- Docker
- GNU Make

### Configure image metadata

Edit `Makefile` values as needed:

```makefile
PERSISTENCE_DIR = $(shell pwd)/data
VERSION = 2.14.0
NAMESPACE = davidliyutong
IMAGE = mlflow
```

Then build:

```bash
make build
```

Push (optional):

```bash
make push
```

## Run with Docker Compose

The provided `docker-compose.yml` starts:

- `db` (MySQL 5.7)
- `mlflow` (Tracking Server on port **8080**)

Update secrets and endpoints in `docker-compose.yml`:

- `MLFLOW_S3_ENDPOINT_URL`
- `MLFLOW_S3_BUCKET`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Start services:

```bash
docker compose up -d
```

Open MLflow UI:

- http://localhost:8080

## Client quickstart connection

From your training code, point MLflow client to this server:

```python
import mlflow
mlflow.set_tracking_uri("http://localhost:8080")
```

This follows the current MLflow quickstart flow of running a tracking server and explicitly setting the tracking URI.

## Notes

- The container entrypoint constructs `MLFLOW_BACKEND_STORE_URI` from `MYSQL_*` environment variables.
- Artifact storage is configured with `--artifacts-destination s3://<bucket>/`.
- If you need local-file artifact storage instead of S3, adjust `entrypoint.sh` accordingly.

## References

- MLflow Tracking Quickstart: https://mlflow.org/docs/latest/ml/getting-started/quickstart/
- Official MLflow Docker image: https://ghcr.io/mlflow/mlflow
