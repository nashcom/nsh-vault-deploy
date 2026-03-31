#!/bin/bash
# 04-pki-acme/setup.sh -- Enable ACME protocol on the intermediate CA with role enforcement
#
# Requires: 03-pki-intermediate-ca completed (pki-intermediate/ engine must exist)
# Requires: Vault 1.14+
#
# Usage:
#   cd server/provisioners/04-pki-acme
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

header "04-pki-acme Configuration"

GetInput VAULT_ADDR    "Vault address"
GetInput VAULT_TOKEN   "Vault root token"
GetInput VAULT_API_ADDR "Public Vault URL (e.g. https://vault.example.com)"
GetInput VAULT_DOMAIN   "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

echo "  External URL : $VAULT_API_ADDR"
echo "  PKI domain   : $VAULT_DOMAIN"
echo "  ACME directory will be at: ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory"


header "Checking intermediate PKI engine"

if ! vault secrets list -format=json | jq -e '."pki-intermediate/"' >/dev/null 2>&1; then
  echo "ERROR: PKI intermediate secrets engine not found." >&2
  echo "  Run 03-pki-intermediate-ca/setup.sh first." >&2
  exit 1
fi

echo "  pki-intermediate/ found"


header "Tuning PKI mount for ACME response headers"

# Vault filters non-standard response headers by default.
# Replay-Nonce is required: ACME clients use it to prevent replay attacks.
# Link is required: ACME responses include Link headers for ToS and chain URLs.
vault secrets tune \
  -allowed-response-headers="Replay-Nonce" \
  -allowed-response-headers="Link" \
  -allowed-response-headers="Location" \
  pki-intermediate


header "Creating role: acme on intermediate"

vault write pki-intermediate/roles/acme \
  allowed_domains="${VAULT_DOMAIN}" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_wildcard_certificates=false \
  max_ttl=2160h \
  key_type=any \
  require_cn=false \
  no_store=false \
  allow_ip_sans=false


header "Configuring PKI cluster path"

vault write pki-intermediate/config/cluster \
  path="${VAULT_API_ADDR}/v1/pki-intermediate"


header "Enabling ACME on pki-intermediate/ with role enforcement"

vault write pki-intermediate/config/acme \
  enabled=true \
  default_directory_policy="role:acme"

# role:acme enforces that ACME clients must use the 'acme' role
# which restricts domains to ${VAULT_DOMAIN} and subdomains


log "04-pki-acme complete"

# Save configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN VAULT_API_ADDR VAULT_DOMAIN

echo "  ACME directory : ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory"
echo "  Domain policy  : Only ${VAULT_DOMAIN} and subdomains allowed"
echo
echo "  Verify:"
echo "    vault read pki-intermediate/config/acme"
echo "    vault read pki-intermediate/config/cluster"
echo "    vault read pki-intermediate/roles/acme"
echo "    curl -s ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory | jq ."
echo
echo "  Issue with acme.sh:"
echo "    acme.sh --issue --server ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory \\"
echo "      -d test.${VAULT_DOMAIN} --standalone"
echo
echo "  Issue with certbot:"
echo "    certbot certonly --server ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory \\"
echo "      --standalone -d test.${VAULT_DOMAIN}"
