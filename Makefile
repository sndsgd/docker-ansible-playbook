CWD := $(shell pwd)

ANSIBLE_VERSION ?= 2.9.14

IMAGE_NAME ?= sndsgd/docker-ansible-playbook
IMAGE := $(IMAGE_NAME):$(ANSIBLE_VERSION)

USER_SSH_DIR ?= $(HOME)/.ssh

OS_NAME=$(shell uname)
ifeq ($(OS_NAME),Linux)
	SSH_AGENT_SOCK = $(SSH_AUTH_SOCK)
	HOST_IP ?= $(shell hostname -I | cut -d' ' -f1)
else ($(OS_NAME),Darwin)
	SSH_AGENT_SOCK = /run/host-services/ssh-auth.sock
	HOST_IP ?= $(shell ifconfig en0 | grep inet | grep -v inet6 | awk '{print $$2}')
else
	$(error unknown host os is not supported)
endif

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[33m%s\033[0m~%s\n", $$1, $$2}' \
	| column -s "~" -t

IMAGE_ARGS ?= --quiet
.PHONY: image
image: ## Build the docker image
	@echo "building image..."
	@docker build \
	  $(IMAGE_ARGS) \
		--build-arg ANSIBLE_VERSION=$(ANSIBLE_VERSION) \
		--tag $(IMAGE_NAME):latest \
		--tag $(IMAGE) \
		$(CWD)

.PHONY: push
push: ## Push the docker image
push: test-local
	@docker push $(IMAGE)
	@docker push $(IMAGE_NAME):latest

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
