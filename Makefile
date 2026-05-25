.PHONY: help setup secrets build up down logs test scale load-test clean

COMPOSE = docker compose
TAG ?= latest

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: secrets ## First-time setup: generate secrets and build images
	$(COMPOSE) build --parallel
	@echo "✅ Setup complete. Run 'make up' to start services."

secrets: ## Generate secret files (if not present)
	@mkdir -p secrets
	@[ -f secrets/hodor_secret_key.txt ] || \
	  openssl rand -hex 32 > secrets/hodor_secret_key.txt && echo "Generated hodor secret"
	@[ -f secrets/bran_secret_key.txt ] || \
	  openssl rand -hex 32 > secrets/bran_secret_key.txt && echo "Generated bran secret"

build: ## Build all Docker images
	$(COMPOSE) build --parallel --no-cache

up: ## Start all services
	$(COMPOSE) up -d
	@echo "🚀 Services up!"
	@echo "  Hodor: http://localhost:8080/hodor/"
	@echo "  Bran:  http://localhost:8080/bran/"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Grafana: http://localhost:3000 (admin/admin)"

down: ## Stop all services
	$(COMPOSE) down

logs: ## Tail logs for all services
	$(COMPOSE) logs -f hodor bran nginx

test: ## Run smoke tests against running stack
	@bash scripts/smoke_test.sh

load-test: ## Run load test with oha (must be installed)
	@bash scripts/load_test.sh

scale-hodor: ## Scale hodor replicas (REPLICAS=N)
	$(COMPOSE) up -d --scale hodor=$(REPLICAS)

scale-bran: ## Scale bran replicas (REPLICAS=N)
	$(COMPOSE) up -d --scale bran=$(REPLICAS)

clean: ## Remove containers, images, volumes
	$(COMPOSE) down -v --rmi local
	rm -rf secrets/

status: ## Show running containers
	$(COMPOSE) ps
