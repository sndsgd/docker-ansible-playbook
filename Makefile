SHELL := /usr/bin/env bash
CWD := $(shell pwd)

PYTHON_VERSION ?= 3.13
ANSIBLE_VERSION ?=
FETCHED_ANSIBLE_VERSION ?=

NAME := sndsgd/ansible-playbook
IMAGE_NAME ?= ghcr.io/$(NAME)
LATEST_IMAGE := $(IMAGE_NAME):latest

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[33m%s\033[0m~%s\n", $$1, $$2}' \
	| column -s "~" -t

VERSION_URL ?= https://pypi.org/pypi/ansible/json
.PHONY: ensure-version
ensure-version:
ifeq ($(ANSIBLE_VERSION),)
	@$(info fetching latest version...)
	@$(eval ANSIBLE_VERSION = $(shell curl -fsSL $(VERSION_URL) | jq -r .info.version))
	@$(eval FETCHED_ANSIBLE_VERSION = $(ANSIBLE_VERSION))
	@echo "found ansible version $(ANSIBLE_VERSION)"
endif
	@$(eval IMAGE := $(IMAGE_NAME):$(ANSIBLE_VERSION))

IMAGE_ARGS ?= --quiet
.PHONY: image
image: ## Build the docker image
image: ensure-version
	@$(info building ansible v$(ANSIBLE_VERSION) image...)
	@docker build \
	  $(IMAGE_ARGS) \
		--build-arg PYTHON_VERSION=$(PYTHON_VERSION) \
		--build-arg ANSIBLE_VERSION=$(ANSIBLE_VERSION) \
		--tag $(IMAGE) \
		$(CWD)
ifeq ($(ANSIBLE_VERSION),$(FETCHED_ANSIBLE_VERSION))
	@docker tag $(IMAGE) $(LATEST_IMAGE)
endif

.PHONY: push
push: ## Push the docker image
push: test-local
	docker push $(IMAGE)
ifeq ($(ANSIBLE_VERSION),$(FETCHED_ANSIBLE_VERSION))
	docker push $(LATEST_IMAGE)
endif

.PHONY: push-cron
push-cron: ## Build and push an image if the version does not exist
push-cron: ensure-version
	@token_response="$$(curl --silent -f -lSL "https://ghcr.io/token?scope=repository:$(NAME):pull")"; \
	token="$$(echo "$$token_response" | jq -r .token)"; \
	json="$$(curl --silent -f -lSL -H "Authorization: Bearer $$token" https://ghcr.io/v2/$(NAME)/tags/list)"; \
	index="$$(echo "$$json" | jq '.tags | index("$(ANSIBLE_VERSION)")')"; \
	if [ "$$index" = "null" ] || [ -z "$$index" ]; then \
		$(MAKE) --no-print-directory push ANSIBLE_VERSION=$(ANSIBLE_VERSION) FETCHED_ANSIBLE_VERSION=$(ANSIBLE_VERSION) IMAGE_ARGS=--no-cache; \
	else \
		echo "image for '$(ANSIBLE_VERSION)' already exists"; \
	fi

IS_TTY:=$(shell [ -t 0 ] && echo 1)
ifdef IS_TTY
	DOCKER_DEFAULT_OPTIONS ?= -it --rm
else
	DOCKER_DEFAULT_OPTIONS ?= --rm
endif

USER_SSH_DIR ?= $(HOME)/.ssh
SSH_AGENT_SOCK = $(SSH_AUTH_SOCK)

TEST_PLAYBOOK ?= test.yml
TEST_HOST ?=
TEST_PORT ?= 22
TEST_USER ?= $(shell whoami)
TEST_EXTRA_VARS ?= '{}'

.PHONY: ensure-test-host
ensure-test-host:
ifeq ($(TEST_HOST),)
	$(error TEST_HOST is required, eg: make test-host TEST_HOST=example.com)
endif

.PHONY: test-host
test-host: ## Test against TEST_HOST using ssh from the container
test-host: ensure-test-host image
	docker run \
		$(DOCKER_DEFAULT_OPTIONS) \
		-v $(USER_SSH_DIR)/id_rsa:/root/.ssh/id_rsa \
		-v $(USER_SSH_DIR)/id_rsa.pub:/root/.ssh/id_rsa.pub \
		-v $(USER_SSH_DIR)/known_hosts:/root/.ssh/known_hosts:ro \
		-v $(SSH_AGENT_SOCK):$(SSH_AGENT_SOCK) \
		-e SSH_AUTH_SOCK=$(SSH_AGENT_SOCK) \
		-v $(CWD):$(CWD) \
		-w $(CWD) \
		$(IMAGE) \
		--inventory $(TEST_HOST), \
		--extra-vars=ansible_port=$(TEST_PORT) \
		--extra-vars=$(TEST_EXTRA_VARS) \
		--user=$(TEST_USER) \
		--ask-become-pass \
		$(TEST_PLAYBOOK)

.PHONY: test-local
test-local: ## Test against the container from within the container
test-local: image
	docker run \
		$(DOCKER_DEFAULT_OPTIONS) \
		-e ANSIBLE_PYTHON_INTERPRETER=/usr/local/bin/python \
		-v $(CWD):$(CWD) \
		-w $(CWD) \
		$(IMAGE) \
		--connection=local \
		--inventory 127.0.0.1, \
		--extra-vars=$(TEST_EXTRA_VARS) \
		$(TEST_PLAYBOOK)

.PHONY: run-help
run-help: ## Run `ansible-playbook --help`
run-help: image
	@docker run --rm $(IMAGE) --help

.PHONY: run-version
run-version: ## Run `ansible-playbook --version`
run-version: image
	@docker run --rm $(IMAGE) --version

.DEFAULT_GOAL := help
