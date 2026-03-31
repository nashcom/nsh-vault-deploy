#!/bin/bash
# 01-kv-secrets/setup.sh -- KV v2 secrets engine + CertMgr AppRole
#
# Usage:
#   cd server/provisioners/01-kv-secrets
#   bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../script_lib.sh"

INIT_FILE="${SCRIPT_DIR}/../../../server/init/vault-init.json"
ENV_FILE="${SCRIPT_DIR}/../../../.env"

# Load configuration from .env if it exists
if [ -f "$ENV_FILE" ]; then
  LoadEnvFile "$ENV_FILE"
  echo "Loaded configuration from: $ENV_FILE"
fi

LoadVaultToken "$INIT_FILE"

header "01-kv-secrets Configuration"

GetInput VAULT_ADDR "Vault address"
GetInput VAULT_TOKEN "Vault root token"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI


header "Enabling KV v2 at secret/"

vault secrets enable -path=secret kv-v2 2>/dev/null \
  && echo "  enabled" \
  || echo "  already enabled"


header "Writing certmgr-push policy"

vault policy write certmgr-push - < "$SCRIPT_DIR/certmgr-push.hcl"


header "Enabling AppRole auth"

vault auth enable approle 2>/dev/null \
  && echo "  enabled" \
  || echo "  already enabled"


header "Creating certmgr AppRole"

vault write auth/approle/role/certmgr \
  token_policies="certmgr-push" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0   # non-expiring; rotate manually when needed

CERTMGR_ROLE_ID=$(vault read -field=role_id auth/approle/role/certmgr/role-id)
CERTMGR_SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/certmgr/secret-id)

OUTPUT_FILE="${SCRIPT_DIR}/certmgr-approle.env"
printf 'VAULT_ADDR=%s\nVAULT_ROLE_ID=%s\nVAULT_SECRET_ID=%s\n' \
  "$VAULT_ADDR" "$CERTMGR_ROLE_ID" "$CERTMGR_SECRET_ID" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

log "certmgr credentials saved to: $OUTPUT_FILE"

# Save provisioner configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN

echo "  Verify:"
echo "    vault secrets list"
echo "    vault auth list"
echo "    vault policy read certmgr-push"
echo "    vault read auth/approle/role/certmgr"
