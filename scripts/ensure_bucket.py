#!/usr/bin/env python3
"""Create the MLflow artifact bucket if it does not exist.

Waits for the S3-compatible endpoint to become reachable, then ensures the
configured bucket exists. Used by the `rustfs-init` service in
docker-compose.yml.

Environment:
    MLFLOW_S3_ENDPOINT_URL   S3 endpoint URL (default http://rustfs:9000)
    MLFLOW_S3_BUCKET         Bucket name (default mlflow)
    AWS_ACCESS_KEY_ID        Access key
    AWS_SECRET_ACCESS_KEY    Secret key
    AWS_DEFAULT_REGION       Region (default us-east-1)
    BUCKET_INIT_TIMEOUT      Seconds to wait for the endpoint (default 90)
"""

import os
import time

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


def endpoint_url() -> str:
    return os.environ.get("MLFLOW_S3_ENDPOINT_URL", "http://rustfs:9000")


def build_client():
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url(),
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def wait_for_endpoint(client, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            client.list_buckets()
            return
        except Exception as exc:
            last_error = exc
            print(f"Waiting for S3 endpoint at {endpoint_url()}: {exc}")
            time.sleep(2)

    raise SystemExit(f"S3 endpoint was not ready before timeout: {last_error}")


def ensure_bucket(client, bucket: str) -> None:
    try:
        client.head_bucket(Bucket=bucket)
        print(f"Bucket already exists: {bucket}")
    except ClientError as exc:
        status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
        code = exc.response.get("Error", {}).get("Code")
        if status == 404 or code in {"404", "NoSuchBucket"}:
            client.create_bucket(Bucket=bucket)
            print(f"Bucket created: {bucket}")
        else:
            raise


def main() -> None:
    bucket = os.environ.get("MLFLOW_S3_BUCKET", "mlflow")
    timeout = int(os.environ.get("BUCKET_INIT_TIMEOUT", "90"))

    client = build_client()
    wait_for_endpoint(client, timeout)
    ensure_bucket(client, bucket)


if __name__ == "__main__":
    main()
