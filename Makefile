.PHONY: help deploy up down restart logs ps backup backup-setup authelia-setup authelia-password bootstrap

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy or update the full stack
	bash scripts/deploy.sh

up: ## Start all services
	docker compose up -d

down: ## Stop all services
	docker compose down

restart: ## Restart all services
	docker compose restart

logs: ## Tail logs for all services
	docker compose logs -f --tail=100

ps: ## Show running services
	docker compose ps

backup: ## Run backup (local + offsite to Storage Box)
	bash scripts/backup.sh

backup-setup: ## Setup Hetzner Storage Box SSH key + daily cron
	@echo ">>> Installing daily backup cron (3:00 AM)..."
	@(crontab -l 2>/dev/null | grep -v "scripts/backup.sh"; echo "0 3 * * * cd $(shell pwd) && bash scripts/backup.sh >> backups/cron.log 2>&1") | crontab -
	@echo ">>> Cron installed. Check with: crontab -l"

authelia-setup: ## Generate Authelia secrets (run once)
	@echo "Generating Authelia secrets..."
	@mkdir -p authelia/secrets
	@openssl rand -hex 32 > authelia/secrets/jwt_secret
	@openssl rand -hex 32 > authelia/secrets/session_secret
	@openssl rand -hex 32 > authelia/secrets/storage_encryption_key
	@echo ">>> Secrets written to authelia/secrets/"

authelia-password: ## Generate Authelia user password hash
	@docker run --rm -it authelia/authelia:4 authelia crypto hash generate argon2

bootstrap: ## Run server bootstrap (root only)
	bash scripts/bootstrap.sh

traefik-logs: ## Tail Traefik logs
	docker compose logs -f traefik

shell-%: ## Open shell in container: make shell-wordpress1
	docker compose exec $* sh
