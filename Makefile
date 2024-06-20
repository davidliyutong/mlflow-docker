PERSISTENCE_DIR = $(shell pwd)/data
VERSION = 2.14.0
NAMESPACE = davidliyutong
IMAGE = mlflow

.PHONY: all

all: build

build:
	docker build --build-arg VERSION=${VERSION} -t ${NAMESPACE}/${IMAGE}:${VERSION} .
	docker tag ${NAMESPACE}/mlflow:${VERSION} ${NAMESPACE}/${IMAGE}:latest

push:
	docker push ${NAMESPACE}/mlflow:${VERSION}
	docker push ${NAMESPACE}/${IMAGE}:latest

dev:
	docker run --rm -p 5000:5000 -v ${PERSISTENCE_DIR}:/data  ${NAMESPACE}/${IMAGE}:latest