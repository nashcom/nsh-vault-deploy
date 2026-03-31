#!/bin/bash
# 02-pki-internal-ca/setup.sh -- PKI secrets engine + internal root CA
#
# Usage:
#   cd server/provisioners/02-pki-internal-ca
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

header "02-pki-internal-ca Configuration"

GetInput VAULT_ADDR    "Vault address"
GetInput VAULT_TOKEN   "Vault root token"
GetInput VAULT_API_ADDR "Public Vault URL (e.g. https://vault.example.com)"
GetInput VAULT_DOMAIN   "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

echo "  External URL : $VAULT_API_ADDR"
echo "  PKI domain   : $VAULT_DOMAIN"


header "Enabling PKI secrets engine at pki/"

vault secrets enable pki 2>/dev/null \
  && echo "  enabled" \
  || echo "  already enabled"


header "Tuning max lease TTL to 10 years"

vault secrets tune -max-lease-ttl=87600h pki


header "Generating internal root CA"

CA_CERT_FILE="${SCRIPT_DIR}/root-ca.crt"

vault write -format=json pki/root/generate/internal \
  common_name="Vault Internal Root CA" \
  organization="Lab" \
  ttl=87600h \
  key_type=ec \
  key_bits=256 \
  | jq -r '.data.certificate' > "$CA_CERT_FILE"

echo "  Root CA saved to: $CA_CERT_FILE"


header "Configuring PKI issuer URLs"

vault write pki/config/urls \
  issuing_certificates="${VAULT_API_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_API_ADDR}/v1/pki/crl" \
  ocsp_servers="${VAULT_API_ADDR}/v1/pki/ocsp"


header "Configuring CRL (24h expiry, auto-rebuild)"

vault write pki/config/crl \
  expiry="24h" \
  auto_rebuild=true \
  auto_rebuild_grace_period="12h"


header "Creating role: server"

vault write pki/roles/server \
  allowed_domains="${VAULT_DOMAIN}" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_wildcard_certificates=false \
  max_ttl=720h \
  key_type=ec \
  key_bits=256 \
  require_cn=true \
  no_store=false


log "02-pki-internal-ca complete"

# Save provisioner configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN VAULT_API_ADDR VAULT_DOMAIN

echo "  Root CA  : $CA_CERT_FILE"
echo "  CA URL   : ${VAULT_API_ADDR}/v1/pki/ca/pem"
echo "  CRL URL  : ${VAULT_API_ADDR}/v1/pki/crl"
echo
echo "  Verify:"
echo "    vault secrets list"
echo "    vault read pki/config/urls"
echo "    vault list pki/roles"
echo
echo "  Issue a test cert:"
echo "    vault write pki/issue/server common_name=test.${VAULT_DOMAIN} ttl=24h"
