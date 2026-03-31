#!/bin/bash
# 05-approle-nginx/setup.sh -- Create per-server AppRole for NGINX cert delivery
#
# Usage:
#   cd server/provisioners/05-approle-nginx
#   bash setup.sh <server-fqdn>
#
# Example:
#   bash setup.sh nginx01.example.com

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

header "05-approle-nginx Configuration"

GetInput VAULT_ADDR  "Vault address"
GetInput VAULT_TOKEN "Vault root token"

HOSTNAME="${1:-}"
GetInput HOSTNAME "Server FQDN (e.g. nginx01.example.com)"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

echo "  Server FQDN : $HOSTNAME"


header "Writing policy: nginx-${HOSTNAME}"

sed "s/SERVER_HOSTNAME/${HOSTNAME}/g" "$SCRIPT_DIR/nginx-read.hcl.tpl" \
  | vault policy write "nginx-${HOSTNAME}" -


header "Creating AppRole: nginx-${HOSTNAME}"

vault write "auth/approle/role/nginx-${HOSTNAME}" \
  token_policies="nginx-${HOSTNAME}" \
  token_ttl=2h \
  token_max_ttl=8h \
  secret_id_ttl=0   # non-expiring; rotate manually

ROLE_ID=$(vault read -field=role_id "auth/approle/role/nginx-${HOSTNAME}/role-id")
SECRET_ID=$(vault write -force -field=secret_id "auth/approle/role/nginx-${HOSTNAME}/secret-id")

CREDS_DIR="${SCRIPT_DIR}/credentials/${HOSTNAME}"
mkdir -p "$CREDS_DIR"

printf '%s' "$ROLE_ID"   > "${CREDS_DIR}/role_id"
printf '%s' "$SECRET_ID" > "${CREDS_DIR}/secret_id"
chmod 600 "${CREDS_DIR}/role_id" "${CREDS_DIR}/secret_id"


log "05-approle-nginx complete for $HOSTNAME"

echo "  Role ID    : $ROLE_ID"
echo "  Credentials: $CREDS_DIR"
echo
echo "  Copy to NGINX server:"
echo "    scp ${CREDS_DIR}/{role_id,secret_id} root@${HOSTNAME}:/etc/vault-agent/"
echo
echo "  Verify:"
echo "    vault read auth/approle/role/nginx-${HOSTNAME}"
echo "    vault policy read nginx-${HOSTNAME}"
