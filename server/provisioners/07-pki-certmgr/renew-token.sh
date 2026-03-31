#!/bin/bash
# renew-token.sh -- Generate a new 48h token for Domino CertMgr
#
# Use this to refresh the CertMgr token without re-running the full provisioner.
# Tokens expire after 48 hours; run this script to get a fresh one.
#
# Usage:
#   cd server/provisioners/07-pki-certmgr
#   bash renew-token.sh

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

header "Generating new CertMgr token (48h TTL)"

GetInput VAULT_ADDR  "Vault address"
GetInput VAULT_TOKEN "Vault root token"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

# Create new token
TOKEN_RESPONSE=$(vault token create -format=json -policy=domino-certmgr -ttl=48h)

TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.auth.client_token')
TOKEN_ACCESSOR=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.auth.accessor')
TOKEN_TTL=$(printf '%s' "$TOKEN_RESPONSE" | jq -r '.auth.lease_duration')

log "CertMgr token generated successfully"

echo "  Token        : $TOKEN"
echo "  Accessor     : $TOKEN_ACCESSOR"
echo "  TTL          : ${TOKEN_TTL}s (48 hours)"
echo
echo "  Expires      : $(date -d "+${TOKEN_TTL}s" 2>/dev/null || echo '~48 hours from now')"
echo
echo "  Copy token to CertMgr configuration:"
echo "    export VAULT_TOKEN=$TOKEN"
