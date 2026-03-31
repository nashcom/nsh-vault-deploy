#!/bin/bash
# setup-provisioners.sh -- Run all provisioners non-interactively
#
# Prerequisites:
#   - .env file exists (created by setup-vault.sh)
#   - Vault is initialized and unsealed (run server/init/setup.sh)
#
# Usage:
#   bash setup-provisioners.sh
#
# This will run all 7 provisioners without prompting (uses .env values).
# Per-server provisioners (05, 06) use defaults or environment overrides.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/script_lib.sh"

ENV_FILE="${SCRIPT_DIR}/.env"
INTERACTIVE=false

# Load configuration
if [ ! -f "$ENV_FILE" ]; then
  header "Configuration Missing"
  echo "No .env file found. This is needed before running provisioners."
  echo
  read -r -p "Run ./setup-vault.sh now? (y/n) " -n 1
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/setup-vault.sh"
  else
    echo "Cancelled."
    exit 0
  fi
fi

LoadEnvFile "$ENV_FILE"

header "Vault Provisioning"
echo "Configuration file: $ENV_FILE"
echo "Mode: Non-interactive (INTERACTIVE=false)"
echo

# Make sure we have required variables
for var in VAULT_ADDR VAULT_API_ADDR VAULT_DOMAIN; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Required variable $var not set in .env" >&2
    exit 1
  fi
done

export INTERACTIVE VAULT_ADDR VAULT_API_ADDR VAULT_DOMAIN

# Check if provisioning has already been done
SetupVaultCLI
if vault secrets list -format=json 2>/dev/null | jq -e '.["secret/"]' >/dev/null 2>&1; then
  header "ERROR: Provisioning Already Complete"
  echo "The KV secrets engine (secret/) already exists."
  echo "Running this script again will duplicate configuration."
  echo
  echo "If you need to re-provision, use:"
  echo "  ./start-vault.sh --scratch"
  echo "  ./setup-vault.sh"
  echo "  ./setup-provisioners.sh"
  echo
  exit 1
fi

PROVISIONERS=(
  "01-kv-secrets"
  "02-pki-internal-ca"
  "03-pki-intermediate-ca"
  "04-pki-acme"
)

PER_SERVER_PROVISIONERS=(
  "05-approle-nginx"
  "06-mtls-bootstrap"
)

FINAL_PROVISIONERS=(
  "07-pki-certmgr"
)

# Run core provisioners (one-time)
header "Core Provisioners (01-04)"

cd "$SCRIPT_DIR/server/provisioners"

for prov in "${PROVISIONERS[@]}"; do
  if [ -d "$prov" ] && [ -f "$prov/setup.sh" ]; then
    echo
    echo "Running: $prov"
    bash "$prov/setup.sh" || {
      echo "ERROR: $prov failed" >&2
      exit 1
    }
  fi
done


# Run per-server provisioners (with defaults)
header "Per-Server Provisioners (05, 06)"

# Use environment variable or default
SERVER_HOSTNAME="${SERVER_HOSTNAME:-nginx01.example.com}"

echo "Using SERVER_HOSTNAME=$SERVER_HOSTNAME"
echo "(Override with: export SERVER_HOSTNAME=your-server.fqdn)"
echo

for prov in "${PER_SERVER_PROVISIONERS[@]}"; do
  if [ -d "$prov" ] && [ -f "$prov/setup.sh" ]; then
    echo
    echo "Running: $prov"
    if [ "$prov" = "05-approle-nginx" ]; then
      bash "$prov/setup.sh" "$SERVER_HOSTNAME" || {
        echo "ERROR: $prov failed" >&2
        exit 1
      }
    else
      bash "$prov/setup.sh" || {
        echo "ERROR: $prov failed" >&2
        exit 1
      }
    fi
  fi
done


# Run final provisioners
header "Final Provisioners (07)"

for prov in "${FINAL_PROVISIONERS[@]}"; do
  if [ -d "$prov" ] && [ -f "$prov/setup.sh" ]; then
    echo
    echo "Running: $prov"
    bash "$prov/setup.sh" || {
      echo "ERROR: $prov failed" >&2
      exit 1
    }
  fi
done

log "All provisioners completed successfully!"

display_root_token "${SCRIPT_DIR}/server/init/vault-init.json"

echo "Next steps:"
echo
echo "  - Access Vault UI: $VAULT_API_ADDR"
echo "  - Import root CA to browser for trusted access"
echo "  - Deploy clients with credentials from server/provisioners/*/credentials/"
echo
