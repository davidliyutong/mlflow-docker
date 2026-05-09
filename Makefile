PERSISTENCE_DIR = $(shell pwd)/data
VERSION = 2.14.0
NAMESPACE = davidliyutong
IMAGE = mlflow

.PHONY: all build push dev compose-up compose-down smoke

all: build

build:
	docker build --build-arg VERSION=${VERSION} -t ${NAMESPACE}/${IMAGE}:${VERSION} .
	docker tag ${NAMESPACE}/mlflow:${VERSION} ${NAMESPACE}/${IMAGE}:latest

push:
	docker push ${NAMESPACE}/mlflow:${VERSION}
	docker push ${NAMESPACE}/${IMAGE}:latest

dev:
	docker run --rm -p 8080:8080 -v ${PERSISTENCE_DIR}:/data  ${NAMESPACE}/${IMAGE}:latest

compose-up:
	DOCKER_BUILDKIT=0 docker compose up -d --build

compose-down:
	docker compose down

smoke:
	uv run tests/smoke/mlflow_training_smoke.py
