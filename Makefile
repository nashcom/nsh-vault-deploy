.PHONY: help up down logs status shell permissions bootstrap

VAULT_ADDR ?= http://127.0.0.1:8100

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  Server:"
	@echo "    bootstrap  Generate bootstrap TLS cert (run once before 'up')"
	@echo "    up         Start Vault"
	@echo "    down       Stop Vault"
	@echo "    logs       Follow Vault logs"
	@echo "    status     Show Vault status"
	@echo "    shell      Open a shell in the Vault container"
	@echo ""
	@echo "  Setup:"
	@echo "    init       Initialize and unseal Vault (run once after 'up')"
	@echo "    permissions  Set executable bit on all shell scripts"
	@echo ""
	@echo "  Provisioners (run after init):"
	@echo "    prov-kv    Run 01-kv-secrets provisioner"
	@echo "    prov-pki   Run 02-pki-internal-ca provisioner"
	@echo "    prov-acme  Run 03-pki-acme provisioner"

# ── Server ────────────────────────────────────────────────────────────────────

bootstrap:
	cd server && bash tls/bootstrap.sh vault.example.com

up:
	cd server && docker compose up -d

down:
	cd server && docker compose down

logs:
	cd server && docker compose logs -f vault

status:
	vault status -address=$(VAULT_ADDR) || true

shell:
	docker exec -it -e VAULT_ADDR=$(VAULT_ADDR) vault sh

# ── Setup ─────────────────────────────────────────────────────────────────────

init:
	cd server && bash init/setup.sh

permissions:
	find . -name "*.sh" -exec chmod +x {} \;
	@echo "Done — all .sh files are now executable"

# ── Provisioners ──────────────────────────────────────────────────────────────
# These use VAULT_ADDR and VAULT_TOKEN from the environment.
# Export them first:
#   export VAULT_ADDR=http://127.0.0.1:8100
#   export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)

prov-kv:
	bash provisioners/01-kv-secrets/setup.sh

prov-pki:
	bash provisioners/02-pki-internal-ca/setup.sh

prov-acme:
	bash provisioners/03-pki-acme/setup.sh
