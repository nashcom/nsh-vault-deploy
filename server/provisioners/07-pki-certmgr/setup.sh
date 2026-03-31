#!/bin/bash
# 07-pki-certmgr/setup.sh -- PKI role and token for Domino CertMgr
#
# Requires: 04-pki-acme completed (pki-intermediate/ engine with roles)
#
# Usage:
#   cd server/provisioners/07-pki-certmgr
#   bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../script_lib.sh"

ENV_FILE="${SCRIPT_DIR}/../../../.env"

# Load configuration from .env if it exists
if [ -f "$ENV_FILE" ]; then
  LoadEnvFile "$ENV_FILE"
  echo "Loaded configuration from: $ENV_FILE"
fi

INIT_FILE="${SCRIPT_DIR}/../../../server/init/vault-init.json"

LoadVaultToken "$INIT_FILE"

header "07-pki-certmgr Configuration"

GetInput VAULT_ADDR    "Vault address"
GetInput VAULT_TOKEN   "Vault root token"
GetInput VAULT_DOMAIN  "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI


header "Creating domino-certmgr policy"

"$SCRIPT_DIR/../../../vault.sh" policy write domino-certmgr - < "$SCRIPT_DIR/domino-certmgr.hcl"


header "Creating PKI role on intermediate: domino-certmgr"

"$SCRIPT_DIR/../../../vault.sh" write pki-intermediate/roles/domino-certmgr \
  allowed_domains="${VAULT_DOMAIN}" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_wildcard_certificates=false \
  max_ttl="72h" \
  key_type=ec \
  key_bits=256


header "Creating token with domino-certmgr policy"

"$SCRIPT_DIR/../../../vault.sh" token create \
  -policy=domino-certmgr \
  -ttl=48h


log "07-pki-certmgr complete"

# Save configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN VAULT_DOMAIN

echo "  CertMgr can now sign certificates for: ${VAULT_DOMAIN} and subdomains"
echo "  Role enforces domain restrictions (no sign-verbatim bypass)"
echo
echo "  Verify:"
echo "    vault read pki-intermediate/roles/domino-certmgr"
echo "    vault policy read domino-certmgr"
