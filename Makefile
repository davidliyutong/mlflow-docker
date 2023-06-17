PERSISTENCE_DIR = C:/Users/liyutong/Desktop/data
VERSION = 2.2.2
NAMESPACE = davidliyutong
IMAGE = mlflow

.PHONY: all

all: build

build:
	docker build --build-arg VERSION=${VERSION} -t ${NAMESPACE}/${IMAGE}:${VERSION} .
	docker tag davidliyutong/mlflow:${VERSION} ${NAMESPACE}/${IMAGE}:latest

run:
	docker run --rm -p 5000:5000 -v ${PERSISTENCE_DIR}:/data  ${NAMESPACE}/${IMAGE}:latest