.PHONY: deploy deploy-service backup boot-fix ssh apt-hold help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

deploy: ## Deploy all files to Rock 5B
	@bash deploy/deploy.sh

deploy-service: ## Deploy single service (make deploy-service SVC=gps)
	@bash deploy/deploy.sh $(SVC)

deploy-dry: ## Dry-run deploy (show what would happen)
	@bash deploy/deploy.sh --dry-run

backup: ## Pull current state from device
	@bash deploy/backup.sh

boot-fix: ## Emergency: fix boot symlinks on device
	@ssh $$(grep ROCK_HOST .env | cut -d= -f2) "sudo bash /opt/carstereo/deploy/boot-fix.sh"

apt-hold: ## Pin dangerous packages on device
	@scp system/apt/apt-hold.sh $$(grep ROCK_USER .env | cut -d= -f2)@$$(grep ROCK_HOST .env | cut -d= -f2):/tmp/
	@ssh $$(grep ROCK_USER .env | cut -d= -f2)@$$(grep ROCK_HOST .env | cut -d= -f2) "bash /tmp/apt-hold.sh"

ssh: ## SSH into the Rock 5B
	@ssh $$(grep ROCK_USER .env | cut -d= -f2)@$$(grep ROCK_HOST .env | cut -d= -f2)
