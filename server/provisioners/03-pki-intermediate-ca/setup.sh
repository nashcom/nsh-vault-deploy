#!/bin/bash
# 03-pki-intermediate-ca/setup.sh -- Intermediate CA signed by root CA
#
# Requires: 02-pki-internal-ca completed (pki/ engine with root CA)
#
# Usage:
#   cd server/provisioners/03-pki-intermediate-ca
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

header "03-pki-intermediate-ca Configuration"

GetInput VAULT_ADDR     "Vault address"
GetInput VAULT_TOKEN    "Vault root token"
GetInput VAULT_API_ADDR "Public Vault URL (e.g. https://vault.example.com)"
GetInput VAULT_DOMAIN   "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

echo "  External URL : $VAULT_API_ADDR"
echo "  PKI domain   : $VAULT_DOMAIN"


header "Enabling PKI at pki-intermediate/"

vault secrets enable -path=pki-intermediate pki 2>/dev/null \
  && echo "  enabled" \
  || echo "  already enabled"


header "Tuning max lease TTL to 10 years"

vault secrets tune -max-lease-ttl=87600h pki-intermediate


header "Generating intermediate CSR"

CSR_RESPONSE=$(vault write -format=json pki-intermediate/intermediate/generate/internal \
  common_name="Vault Intermediate CA" \
  organization="Lab" \
  ttl=43800h \
  key_type=ec \
  key_bits=256)

CSR=$(printf '%s' "$CSR_RESPONSE" | jq -r '.data.csr')

echo "  CSR generated"


header "Signing intermediate with root CA"

CERT_RESPONSE=$(vault write -format=json pki/root/sign-intermediate \
  csr="$CSR" \
  format=pem_bundle \
  ttl=43800h)

INTERMEDIATE_CERT=$(printf '%s' "$CERT_RESPONSE" | jq -r '.data.certificate')
CERT_CHAIN=$(printf '%s' "$CERT_RESPONSE" | jq -r '.data.ca_chain[]' | paste -sd '' -)

echo "  intermediate signed by root"


header "Setting intermediate certificate"

vault write pki-intermediate/intermediate/set-signed \
  certificate="$INTERMEDIATE_CERT"

echo "  intermediate certificate set"


header "Configuring PKI issuer URLs"

vault write pki-intermediate/config/urls \
  issuing_certificates="${VAULT_API_ADDR}/v1/pki-intermediate/ca" \
  crl_distribution_points="${VAULT_API_ADDR}/v1/pki-intermediate/crl" \
  ocsp_servers="${VAULT_API_ADDR}/v1/pki-intermediate/ocsp"


header "Configuring CRL (24h expiry, auto-rebuild)"

vault write pki-intermediate/config/crl \
  expiry="24h" \
  auto_rebuild=true \
  auto_rebuild_grace_period="12h"


header "Saving intermediate CA certificate"

INTER_CERT_FILE="${SCRIPT_DIR}/intermediate-ca.crt"
printf '%s' "$INTERMEDIATE_CERT" > "$INTER_CERT_FILE"
chmod 644 "$INTER_CERT_FILE"

echo "  saved to: $INTER_CERT_FILE"


log "03-pki-intermediate-ca complete"

# Save configuration for next steps
SaveEnvFile "$ENV_FILE" VAULT_ADDR VAULT_TOKEN VAULT_API_ADDR VAULT_DOMAIN

echo "  Intermediate CA : $INTER_CERT_FILE"
echo "  CA URL          : ${VAULT_API_ADDR}/v1/pki-intermediate/ca/pem"
echo "  CRL URL         : ${VAULT_API_ADDR}/v1/pki-intermediate/crl"
echo
echo "  Verify:"
echo "    vault read pki-intermediate/cert/ca_chain"
echo "    vault read pki-intermediate/config/urls"
