SHELL := /usr/bin/env bash
CWD := $(shell pwd)

ANSIBLE_VERSION ?= 2.10.3

IMAGE_NAME ?= sndsgd/ansible-playbook
IMAGE := $(IMAGE_NAME):$(ANSIBLE_VERSION)

USER_SSH_DIR ?= $(HOME)/.ssh

OS_NAME=$(shell uname)
ifeq ($(OS_NAME),Darwin)
	SSH_AGENT_SOCK = /run/host-services/ssh-auth.sock
	HOST_IP ?= $(shell ifconfig en0 | grep inet | grep -v inet6 | awk '{print $$2}')
else
	SSH_AGENT_SOCK = $(SSH_AUTH_SOCK)
	HOST_IP ?= $(shell hostname -I | cut -d' ' -f1)
endif

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[33m%s\033[0m~%s\n", $$1, $$2}' \
	| column -s "~" -t

IMAGE_ARGS ?= --quiet
.PHONY: image
image: ## Build the docker image
	@echo "building ansible v$(ANSIBLE_VERSION) image ..."
	@docker build \
	  $(IMAGE_ARGS) \
		--build-arg ANSIBLE_VERSION=$(ANSIBLE_VERSION) \
		--tag $(IMAGE) \
		$(CWD)

.PHONY: push
push: ## Push the docker image
push: test-local
	@docker push $(IMAGE)

VERSION_URL ?= https://github.com/ansible/ansible/tags
VERSION_PATTERN ?= '(?<=href="/ansible/ansible/releases/tag/v)[^"rc]+(?=")'
ANSIBLE_VERSIONS = $(shell curl -s $(VERSION_URL) | grep -Po $(VERSION_PATTERN) | tr '\n' ' ')
IMAGE_CHECK_URL = https://index.docker.io/v1/repositories/$(IMAGE_NAME)/tags/%s
.PHONY: push-cron
push-cron: ## Fetch latest tags, build and push images if they do not already exist
	for version in $(ANSIBLE_VERSIONS); \
	do \
		echo -n "checking $$version... "; \
		curl --silent -f -lSL $$(printf $(IMAGE_CHECK_URL) "$$version") &> /dev/null; \
		if [ $$? -eq 0 ]; then \
			echo "aleady exists"; \
		else \
			echo "not found; building..."; \
			make --no-print-directory push ANSIBLE_VERSION="$$version" IMAGE_ARGS=--no-cache; \
		fi; \
	done

TEST_PLAYBOOK ?= test.yml
TEST_PORT ?= 22
TEST_EXTRA_VARS ?= '{}'

# Used to ensure that the host's key is in the host's authorized_keys.
# This allows you to share your pubkey into the container, and then use
# it to hit your host machine from the container.
.PHONY: ensure-key-is-authorized
ensure-key-is-authorized:
	@grep -q "$(shell awk '{$$1=$$1};1' $(USER_SSH_DIR)/id_rsa.pub)" $(USER_SSH_DIR)/authorized_keys \
		|| cat $(USER_SSH_DIR)/id_rsa.pub >> $(USER_SSH_DIR)/authorized_keys

.PHONY: test-host
test: ## Test against your host machine using ssh from the container
test: image ensure-key-is-authorized
	docker run --rm -it \
		-v $(USER_SSH_DIR)/id_rsa:/root/.ssh/id_rsa \
		-v $(USER_SSH_DIR)/id_rsa.pub:/root/.ssh/id_rsa.pub \
		-v $(SSH_AGENT_SOCK):$(SSH_AGENT_SOCK) \
		-e SSH_AUTH_SOCK=$(SSH_AGENT_SOCK) \
		-v $(CWD):$(CWD) \
		-w $(CWD) \
		$(IMAGE) \
		--inventory $(HOST_IP), \
		--extra-vars=ansible_port=$(TEST_PORT) \
		--extra-vars=$(TEST_EXTRA_VARS) \
		--user=$(shell whoami) \
		--ask-become-pass \
		$(TEST_PLAYBOOK)

.PHONY: test-local
test-local: ## Test against the container from within the container
test-local: image
	@docker run --rm -it \
		-e ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3 \
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
	@docker run --rm $(IMAGE) --help
