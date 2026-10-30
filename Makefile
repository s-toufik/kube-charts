# kube-charts — check and publish the homelab's Helm charts
# Run `make` or `make help` to list targets.

SHELL         := bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

HELM        ?= helm
KUBECONFORM ?= kubeconform
REGISTRY    ?= oci://ghcr.io/s-toufik/charts
# make check CHART=app
CHART ?=

export HELM KUBECONFORM REGISTRY

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n"} \
	  /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

.PHONY: check
check: ## Lint, render and schema-check every chart (CHART=app for one)
	@./scripts/check.sh $(CHART)

.PHONY: publish
publish: ## Push the chart versions not in the registry yet (CI does this on main)
	@./scripts/publish.sh

.PHONY: clean
clean: ## Remove built packages and vendored dependencies
	rm -rf dist charts/*/charts
