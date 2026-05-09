# MLflow Tracking Server Docker Image

This repository provides a Docker image for running an MLflow Tracking Server backed by:

- **MySQL** for metadata (runs, params, metrics)
- **S3-compatible object storage** (RustFS) for artifacts

It is updated to align with the latest MLflow quickstart workflow (`mlflow server --host 127.0.0.1 --port 8080`) from MLflow docs.

## Build

### Prerequisites

- Docker
- GNU Make
- uv (for the smoke training client)

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
- `rustfs` (S3-compatible artifact storage)
- `mlflow` (Tracking Server on port **8080**)

Start services with the Makefile wrapper:

```bash
make compose-up
```

This runs:

```bash
DOCKER_BUILDKIT=0 docker compose up -d --build
```

Open MLflow UI:

- http://localhost:8080

Open RustFS console:

- http://localhost:9001
- Username: `mlflow`
- Password: `mlflowpassword`

## Client quickstart connection

From your training code, point MLflow client to this server:

```python
import mlflow
mlflow.set_tracking_uri("http://localhost:8080")
```

This follows the current MLflow quickstart flow of running a tracking server and explicitly setting the tracking URI.

Run the included minimum training smoke test:

```bash
make smoke
```

The smoke test creates an MLflow experiment, logs a small training run, records metrics, uploads model metadata, binary weights, a generated loss-curve image, and text/JSONL files, then downloads those artifacts back through the tracking server.

## Notes

- The container entrypoint constructs `MLFLOW_BACKEND_STORE_URI` from `MYSQL_*` environment variables.
- Artifact storage is configured with `--artifacts-destination s3://<bucket>/`.
- The Compose stack creates the `mlflow` bucket in RustFS before starting the tracking server.
- If you need local-file artifact storage instead of S3, adjust `entrypoint.sh` accordingly.

## References

- MLflow Tracking Quickstart: https://mlflow.org/docs/latest/ml/getting-started/quickstart/
- Official MLflow Docker image: https://ghcr.io/mlflow/mlflow
