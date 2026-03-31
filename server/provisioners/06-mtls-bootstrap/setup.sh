#!/bin/bash
# 06-mtls-bootstrap/setup.sh -- Enable cert auth + PKI role for mTLS client certs
#
# Usage:
#   cd server/provisioners/06-mtls-bootstrap
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
CLIENT_CA_OUT="${SCRIPT_DIR}/../../../server/tls/client-ca.crt"

LoadVaultToken "$INIT_FILE"

header "06-mtls-bootstrap Configuration"

GetInput VAULT_ADDR   "Vault address"
GetInput VAULT_TOKEN  "Vault root token"
GetInput VAULT_DOMAIN "Vault domain"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI


header "Enabling cert auth method"

vault auth enable cert 2>/dev/null \
  && echo "  enabled" \
  || echo "  already enabled"


header "Creating PKI role: srvguard-client"

vault write pki/roles/srvguard-client \
  allowed_domains="${VAULT_DOMAIN}" \
  allow_subdomains=true \
  client_flag=true \
  server_flag=false \
  key_type=ec \
  key_bits=256 \
  max_ttl=2160h


header "Exporting PKI root CA cert"

mkdir -p "$(dirname "$CLIENT_CA_OUT")"
vault read -field=certificate pki/cert/ca > "$CLIENT_CA_OUT"
chmod 644 "$CLIENT_CA_OUT"

echo "  written to: $CLIENT_CA_OUT"


log "06-mtls-bootstrap setup complete"

# Save configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN VAULT_DOMAIN

echo "  Client CA cert : $CLIENT_CA_OUT"
echo
echo "  Next: uncomment tls_client_ca_file in server/config/vault.hcl:"
echo "    tls_client_ca_file = \"/vault/tls/client-ca.crt\""
echo
echo "  Then reload Vault TLS:"
echo "    ./vault.sh operator reload"
echo
echo "  Then enroll each server:"
echo "    bash enroll.sh <fqdn>"
