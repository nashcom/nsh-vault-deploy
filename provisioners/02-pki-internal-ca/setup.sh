#!/usr/bin/env bash
# 02-pki-internal-ca/setup.sh — PKI secrets engine + internal root CA
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100
#   export VAULT_TOKEN=<root-token>
#   export VAULT_API_ADDR=https://vault.example.com
#   bash 02-pki-internal-ca/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/../../server/init/vault-init.json}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"

# ── public URL written into PKI configuration ─────────────────────────────────
# VAULT_ADDR (local) is used to connect and run commands.
# VAULT_API_ADDR is different: it gets stored inside Vault as the CRL/OCSP/CA
# issuer URLs that are embedded in every certificate Vault issues.
# Clients validating those certificates will fetch from this URL — it must be
# your public address, not localhost.
if [ -z "${VAULT_API_ADDR:-}" ]; then
  printf "ERROR: VAULT_API_ADDR is required — set it to the public URL of this Vault server.\n" >&2
  printf "  This is not your connection address. It gets written into issued certificates.\n" >&2
  printf "  Example: export VAULT_API_ADDR=https://vault.example.com\n" >&2
  exit 1
fi

# ── token ─────────────────────────────────────────────────────────────────────
if [ -z "${VAULT_TOKEN:-}" ]; then
  if [ -f "$INIT_FILE" ]; then
    VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
  else
    printf "ERROR: VAULT_TOKEN not set and %s not found.\n" "$INIT_FILE" >&2
    printf "  Run server/init/setup.sh first, or: export VAULT_TOKEN=<root-token>\n" >&2
    exit 1
  fi
fi

export VAULT_ADDR VAULT_TOKEN

# ── vault CLI wrapper ─────────────────────────────────────────────────────────
if ! command -v vault >/dev/null 2>&1; then
  vault() { docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" vault vault "$@"; }
fi

printf "=== 02-pki-internal-ca ===\n"
printf "  External URL: %s\n" "$VAULT_API_ADDR"

# ── enable PKI secrets engine ─────────────────────────────────────────────────
printf -- "-- Enabling PKI secrets engine at pki/ --\n"
vault secrets enable pki 2>/dev/null \
  && printf "  enabled\n" \
  || printf "  already enabled\n"

# ── set max lease TTL (must be done before generating root) ───────────────────
printf -- "-- Tuning max lease TTL to 10 years --\n"
vault secrets tune -max-lease-ttl=87600h pki

# ── generate root CA ──────────────────────────────────────────────────────────
printf -- "-- Generating internal root CA --\n"
CA_CERT_FILE="${SCRIPT_DIR}/root-ca.crt"

vault write -format=json pki/root/generate/internal \
  common_name="Vault Internal Root CA" \
  organization="Lab" \
  ttl=87600h \
  key_type=ec \
  key_bits=256 \
  | jq -r '.data.certificate' > "$CA_CERT_FILE"

printf "  Root CA saved to: %s\n" "$CA_CERT_FILE"

# ── configure PKI issuer URLs ─────────────────────────────────────────────────
# These URLs must use the external FQDN — clients will fetch CRL and OCSP from here
printf -- "-- Configuring PKI issuer URLs --\n"
vault write pki/config/urls \
  issuing_certificates="${VAULT_API_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_API_ADDR}/v1/pki/crl" \
  ocsp_servers="${VAULT_API_ADDR}/v1/pki/ocsp"

# ── configure CRL ─────────────────────────────────────────────────────────────
printf -- "-- Configuring CRL (24h expiry, auto-rebuild enabled) --\n"
vault write pki/config/crl \
  expiry="24h" \
  auto_rebuild=true \
  auto_rebuild_grace_period="12h"

# ── create server role ────────────────────────────────────────────────────────
printf -- "-- Creating role: server --\n"
vault write pki/roles/server \
  allowed_domains="example.com" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_wildcard_certificates=false \
  max_ttl=720h \
  key_type=ec \
  key_bits=256 \
  require_cn=true \
  no_store=false

# ── summary ───────────────────────────────────────────────────────────────────
printf "\n=== 02-pki-internal-ca complete ===\n"
printf "  Root CA  : %s\n" "$CA_CERT_FILE"
printf "  CA URL   : %s/v1/pki/ca/pem\n" "$VAULT_API_ADDR"
printf "  CRL URL  : %s/v1/pki/crl\n" "$VAULT_API_ADDR"
printf "\n"
printf "  Verify:\n"
printf "    vault secrets list\n"
printf "    vault read pki/config/urls\n"
printf "    vault list pki/roles\n"
printf "\n"
printf "  Issue a test cert:\n"
printf "    vault write pki/issue/server common_name=test.example.com ttl=24h\n"
