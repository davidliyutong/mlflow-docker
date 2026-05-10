PERSISTENCE_DIR = $(shell pwd)/data
VERSION = 3.12.0
PYTHON_VERSION = 3.12.13
SMOKE_PYTHON = 3.12
NAMESPACE = davidliyutong
IMAGE = mlflow-docker

.PHONY: all build push dev compose-up compose-down smoke FORCE

all: build

build:
	docker build --build-arg VERSION=${VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} -t ${NAMESPACE}/${IMAGE}:${VERSION} .
	docker tag ${NAMESPACE}/${IMAGE}:${VERSION} ${NAMESPACE}/${IMAGE}:latest

push:
	docker push ${NAMESPACE}/${IMAGE}:${VERSION}
	docker push ${NAMESPACE}/${IMAGE}:latest

dev:
	docker run --rm -p 8080:8080 -v ${PERSISTENCE_DIR}:/data  ${NAMESPACE}/${IMAGE}:latest

compose-up:
	DOCKER_BUILDKIT=0 docker compose up -d --build

compose-down:
	docker compose down

smoke:
	uv run --python ${SMOKE_PYTHON} tests/smoke/mlflow_training_smoke.py

print-%: FORCE
	@printf '%s\n' '$($*)'

FORCE:
