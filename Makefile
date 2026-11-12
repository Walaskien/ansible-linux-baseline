.DEFAULT_GOAL := help
IMAGE ?= ubuntu:22.04

.PHONY: help lint syntax test

help: ## Show available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "%-8s %s\n", $$1, $$2}'

lint: ## yamllint and ansible-lint (activate the venv first)
	yamllint .
	ansible-lint

syntax: ## ansible-playbook --syntax-check on site.yml
	ansible-playbook --syntax-check site.yml

test: ## Converge twice in a container, IMAGE=debian:12 to change the OS
	tests/run-in-docker.sh $(IMAGE)
