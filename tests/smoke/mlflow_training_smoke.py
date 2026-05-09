# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "mlflow==2.14.0",
#   "setuptools<81",
# ]
# ///

import argparse
import binascii
import json
import struct
import tempfile
import time
import warnings
import zlib
from pathlib import Path

warnings.filterwarnings(
    "ignore",
    message="pkg_resources is deprecated as an API.*",
    category=UserWarning,
)

import mlflow
from mlflow.tracking import MlflowClient


def wait_for_tracking_server(client: MlflowClient, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            client.search_experiments(max_results=1)
            return
        except Exception as exc:
            last_error = exc
            time.sleep(2)

    raise RuntimeError(f"MLflow tracking server was not ready: {last_error}")


def train_linear_model() -> tuple[float, float, list[float]]:
    xs = [0.0, 1.0, 2.0, 3.0]
    ys = [1.0, 3.0, 5.0, 7.0]
    weight = 0.0
    bias = 0.0
    learning_rate = 0.05
    losses = []

    for _ in range(80):
        predictions = [weight * x + bias for x in xs]
        errors = [prediction - y for prediction, y in zip(predictions, ys)]
        loss = sum(error * error for error in errors) / len(errors)
        losses.append(loss)
        weight_gradient = 2 * sum(error * x for error, x in zip(errors, xs)) / len(xs)
        bias_gradient = 2 * sum(errors) / len(xs)
        weight -= learning_rate * weight_gradient
        bias -= learning_rate * bias_gradient

    return weight, bias, losses


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type)
    checksum = binascii.crc32(data, checksum)
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", checksum & 0xFFFFFFFF)


def write_loss_curve_png(path: Path, losses: list[float]) -> None:
    width = 160
    height = 90
    pixels = bytearray([255, 255, 255] * width * height)

    def set_pixel(x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < width and 0 <= y < height:
            offset = (y * width + x) * 3
            pixels[offset : offset + 3] = bytes(color)

    def draw_line(x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        step_x = 1 if x0 < x1 else -1
        step_y = 1 if y0 < y1 else -1
        error = dx + dy

        while True:
            set_pixel(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            doubled_error = 2 * error
            if doubled_error >= dy:
                error += dy
                x0 += step_x
            if doubled_error <= dx:
                error += dx
                y0 += step_y

    for x in range(10, width - 8):
        set_pixel(x, height - 12, (210, 210, 210))
    for y in range(8, height - 11):
        set_pixel(10, y, (210, 210, 210))

    min_loss = min(losses)
    max_loss = max(losses)
    span = max(max_loss - min_loss, 1e-12)
    points = []
    for index, loss in enumerate(losses):
        x = 12 + round(index * (width - 24) / (len(losses) - 1))
        normalized = (loss - min_loss) / span
        y = height - 14 - round(normalized * (height - 24))
        points.append((x, y))

    for start, end in zip(points, points[1:]):
        draw_line(start[0], start[1], end[0], end[1], (200, 40, 40))

    rows = []
    for y in range(height):
        start = y * width * 3
        rows.append(b"\x00" + bytes(pixels[start : start + width * 3]))

    raw = b"".join(rows)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(raw))
        + png_chunk(b"IEND", b"")
    )


def create_artifacts(root: Path, weight: float, bias: float, losses: list[float]) -> dict[str, bytes]:
    model_path = root / "model.json"
    weights_path = root / "model-weights.bin"
    image_path = root / "loss-curve.png"
    summary_path = root / "training-summary.txt"
    records_path = root / "batch-records.jsonl"

    model_path.write_text(
        json.dumps(
            {
                "weight": weight,
                "bias": bias,
                "final_loss": losses[-1],
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    weights_path.write_bytes(struct.pack("<ddd", weight, bias, losses[-1]))
    write_loss_curve_png(image_path, losses)
    summary_path.write_text(
        "\n".join(
            [
                "MLflow Docker smoke training run",
                f"epochs={len(losses)}",
                f"final_loss={losses[-1]:.12f}",
                f"weight={weight:.12f}",
                f"bias={bias:.12f}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    records_path.write_text(
        "\n".join(
            json.dumps({"epoch": epoch, "loss": loss}, sort_keys=True)
            for epoch, loss in enumerate(losses[::10])
        )
        + "\n",
        encoding="utf-8",
    )

    return {
        "model.json": model_path.read_bytes(),
        "weights/model-weights.bin": weights_path.read_bytes(),
        "images/loss-curve.png": image_path.read_bytes(),
        "files/training-summary.txt": summary_path.read_bytes(),
        "files/batch-records.jsonl": records_path.read_bytes(),
    }


def list_artifact_paths(client: MlflowClient, run_id: str, artifact_path: str | None = None) -> list[str]:
    paths = []
    for artifact in client.list_artifacts(run_id, artifact_path):
        if artifact.is_dir:
            paths.extend(list_artifact_paths(client, run_id, artifact.path))
        else:
            paths.append(artifact.path)
    return sorted(paths)


def verify_artifacts(client: MlflowClient, run_id: str, expected_artifacts: dict[str, bytes]) -> list[str]:
    artifact_paths = list_artifact_paths(client, run_id)
    missing = sorted(set(expected_artifacts) - set(artifact_paths))
    if missing:
        raise RuntimeError(f"Missing expected artifacts: {missing}; found: {artifact_paths}")

    with tempfile.TemporaryDirectory() as download_dir:
        for artifact_path, expected_bytes in expected_artifacts.items():
            downloaded_path = Path(client.download_artifacts(run_id, artifact_path, download_dir))
            actual_bytes = downloaded_path.read_bytes()
            if actual_bytes != expected_bytes:
                raise RuntimeError(f"Downloaded artifact content mismatch: {artifact_path}")

    return artifact_paths


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tracking-uri", default="http://127.0.0.1:8080")
    parser.add_argument("--experiment", default="docker-compose-smoke")
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()

    mlflow.set_tracking_uri(args.tracking_uri)
    client = MlflowClient(tracking_uri=args.tracking_uri)
    wait_for_tracking_server(client, args.timeout)

    experiment = mlflow.set_experiment(args.experiment)
    weight, bias, losses = train_linear_model()

    with mlflow.start_run(run_name="minimum-training-smoke") as run:
        mlflow.log_param("model_type", "linear-regression-from-scratch")
        mlflow.log_param("epochs", len(losses))
        for step, loss in enumerate(losses):
            mlflow.log_metric("loss", loss, step=step)

        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_root = Path(temp_dir)
            expected_artifacts = create_artifacts(artifact_root, weight, bias, losses)
            mlflow.log_artifact(str(artifact_root / "model.json"))
            mlflow.log_artifact(str(artifact_root / "model-weights.bin"), artifact_path="weights")
            mlflow.log_artifact(str(artifact_root / "loss-curve.png"), artifact_path="images")
            mlflow.log_artifact(str(artifact_root / "training-summary.txt"), artifact_path="files")
            mlflow.log_artifact(str(artifact_root / "batch-records.jsonl"), artifact_path="files")

        run_id = run.info.run_id

    finished_run = client.get_run(run_id)
    artifact_paths = verify_artifacts(client, run_id, expected_artifacts)

    print(
        json.dumps(
            {
                "tracking_uri": args.tracking_uri,
                "experiment_id": experiment.experiment_id,
                "run_id": run_id,
                "status": finished_run.info.status,
                "artifact_uri": finished_run.info.artifact_uri,
                "artifacts": artifact_paths,
                "verified_artifact_count": len(expected_artifacts),
                "final_loss": losses[-1],
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
