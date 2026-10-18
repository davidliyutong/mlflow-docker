# MLflow Tracking Server Docker image
#
# Single entrypoint for development, testing and deployment.
# Run `make help` for the target list.
#
# The Makefile is the single source of truth for version pins; run
# `make check-versions` after changing any of them.

SHELL := /bin/bash

# --- Version pins (source of truth) -----------------------------------------
# VERSION is the MLflow version, also used as the image tag.
VERSION        ?= 3.17.1
# PYTHON_VERSION is the CPython base image version.
PYTHON_VERSION ?= 3.12.13
# OIDC_AUTH_VERSION is the mlflow-oidc-auth plugin version (requires MLflow >= 3.16).
OIDC_AUTH_VERSION ?= 11.0.0
# SMOKE_PYTHON is the Python used by `make smoke` (uv managed).
SMOKE_PYTHON   ?= 3.12
# KEYCLOAK_VERSION is pinned for the OIDC demo/test stack only.
KEYCLOAK_VERSION ?= 26.8.1

# --- Image ------------------------------------------------------------------
NAMESPACE ?= davidliyutong
IMAGE     ?= mlflow-docker

# --- Local runtime ----------------------------------------------------------
PERSISTENCE_DIR ?= $(CURDIR)/data
TRACKING_URI    ?= http://127.0.0.1:8080
EXPERIMENT      ?= docker-compose-smoke
OIDC_EXPERIMENT ?= oidc-smoke

COMPOSE_OIDC := docker compose -f docker-compose.yml -f docker-compose.oidc.yml

LOCAL_IMAGE   := $(NAMESPACE)/$(IMAGE):$(VERSION)
LATEST_IMAGE  := $(NAMESPACE)/$(IMAGE):latest
COMPOSE_IMAGE := ghcr.io/$(NAMESPACE)/$(IMAGE):latest

.DEFAULT_GOAL := help
.PHONY: help check-versions lint build push dev up up-oidc down logs logs-oidc smoke test smoke-oidc ci-smoke ci-smoke-oidc clean compose-up compose-down print-% FORCE

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check-versions: ## Verify version pins are in sync across the repo
	@scripts/check-versions.sh

lint: check-versions ## Run static checks (versions, shell, python, compose)
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x scripts/*.sh && echo "shellcheck: ok"; \
	else \
		echo "shellcheck not installed, skipping (CI runs it)"; \
	fi
	@python3 -m py_compile scripts/ensure_bucket.py tests/smoke/*.py && echo "py_compile: ok"
	@docker compose config -q && echo "compose config: ok"
	@$(COMPOSE_OIDC) config -q && echo "compose oidc config: ok"

build: ## Build the image locally (tags VERSION and latest)
	docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
		-t $(LOCAL_IMAGE) .
	docker tag $(LOCAL_IMAGE) $(LATEST_IMAGE)

push: build ## Push the locally built image to the configured namespace
	docker push $(LOCAL_IMAGE)
	docker push $(LATEST_IMAGE)

dev: ## Run a standalone server (sqlite + local artifacts) on port 8080
	mkdir -p "$(PERSISTENCE_DIR)"
	docker run --rm -p 8080:8080 -v "$(PERSISTENCE_DIR):/data" \
		-e MLFLOW_BACKEND_STORE_URI=sqlite:////data/mlflow.db \
		-e MLFLOW_ARTIFACTS_DESTINATION=/data/artifacts \
		$(LOCAL_IMAGE)

up: ## Start the compose stack (builds the image if needed)
	MLFLOW_VERSION=$(VERSION) PYTHON_VERSION=$(PYTHON_VERSION) MLFLOW_OIDC_AUTH_VERSION=$(OIDC_AUTH_VERSION) docker compose up -d --build

up-oidc: ## Start the stack with the demo Keycloak (OIDC enabled)
	KEYCLOAK_VERSION=$(KEYCLOAK_VERSION) \
		MLFLOW_VERSION=$(VERSION) PYTHON_VERSION=$(PYTHON_VERSION) MLFLOW_OIDC_AUTH_VERSION=$(OIDC_AUTH_VERSION) \
		$(COMPOSE_OIDC) up -d --build

down: ## Stop the compose stack (keeps volumes)
	docker compose down --remove-orphans

logs: ## Follow compose logs
	docker compose logs -f

logs-oidc: ## Follow compose logs for the OIDC demo stack
	$(COMPOSE_OIDC) logs -f

# MLflow >= 3.13 downloads artifacts via presigned S3 URLs by default; from the
# host the internal rustfs:9000 endpoint is unreachable, so use proxied
# downloads (see docs/deployment.md).
smoke: ## Run the smoke test against the running stack
	MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false uv run --python $(SMOKE_PYTHON) tests/smoke/mlflow_training_smoke.py \
		--tracking-uri $(TRACKING_URI) --experiment $(EXPERIMENT)

test: smoke ## Alias of `smoke`

smoke-oidc: ## Run the OIDC smoke test (inside the compose network)
	$(COMPOSE_OIDC) run --rm oidc-smoke /tests/smoke/mlflow_oidc_smoke.py \
		--mlflow-uri http://mlflow:8080 --keycloak-uri http://keycloak:8180 \
		--experiment $(OIDC_EXPERIMENT)

ci-smoke: up ## Start the stack, run the smoke test, always tear down
	@set -e; trap '$(MAKE) --no-print-directory down' EXIT; $(MAKE) --no-print-directory smoke

ci-smoke-oidc: up-oidc ## Start the OIDC demo stack, run the OIDC smoke test, always tear down
	@set -e; trap '$(MAKE) --no-print-directory down' EXIT; $(MAKE) --no-print-directory smoke-oidc

clean: ## Stop the stack and delete volumes and the local images
	docker compose down --volumes --remove-orphans
	-docker image rm $(LOCAL_IMAGE) $(LATEST_IMAGE) $(COMPOSE_IMAGE)

compose-up: up ## Alias of `up` (kept for backwards compatibility)

compose-down: down ## Alias of `down` (kept for backwards compatibility)

print-%: FORCE
	@printf '%s\n' '$($*)'

FORCE:
