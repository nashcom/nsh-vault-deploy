#!/usr/bin/env bash
# 02-pki-internal-ca/setup.sh — PKI secrets engine + internal root CA
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100      # local connection (always)
#   export VAULT_TOKEN=<root-token>
#   export VAULT_API_ADDR=https://vault.example.com   # public URL — written into certs
#   export VAULT_DOMAIN=example.com                   # domain for PKI role
#   bash 02-pki-internal-ca/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/../../server/init/vault-init.json}"

# ── interactive input helper ──────────────────────────────────────────────────
# Usage: ask VAR "Description" ["default"]
# If VAR is already set (env var), does nothing.
# Otherwise prompts the user, applies the default if they press Enter, and errors if empty.
ask() {
  local _var="$1" _desc="$2" _default="${3:-}" _value
  eval "_value=\${${_var}:-}"
  [ -n "$_value" ] && return 0
  [ -n "$_default" ] \
    && printf "  %s [%s]: " "$_desc" "$_default" \
    || printf "  %s: " "$_desc"
  read -r _value </dev/tty
  _value="${_value:-$_default}"
  if [ -z "$_value" ]; then
    printf "ERROR: %s is required.\n" "$_var" >&2; exit 1
  fi
  eval "${_var}=\${_value}"; export "${_var?}"
}

# ── required variables ────────────────────────────────────────────────────────
printf "\n=== Configuration ===\n"
printf "  VAULT_ADDR     — how to connect to Vault (local, never the public URL)\n"
ask VAULT_ADDR "Vault address" "http://127.0.0.1:8100"

printf "  VAULT_TOKEN    — root token from server/init/setup.sh\n"
if [ -z "${VAULT_TOKEN:-}" ]; then
  if [ -f "$INIT_FILE" ]; then
    VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    printf "  (token read from %s)\n" "$INIT_FILE"
  else
    ask VAULT_TOKEN "Vault root token"
  fi
fi

printf "  VAULT_API_ADDR — public URL written INTO Vault config (CRL/OCSP/ACME URLs in certs)\n"
printf "                   must be reachable by clients — not localhost\n"
ask VAULT_API_ADDR "Public Vault URL (e.g. https://vault.example.com)"

printf "  VAULT_DOMAIN   — domain for which this CA will issue certificates\n"
printf "                   allow_subdomains=true covers host.example.com, app.example.com, etc.\n"
ask VAULT_DOMAIN "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

# ── vault CLI wrapper ─────────────────────────────────────────────────────────
if ! command -v vault >/dev/null 2>&1; then
  vault() { docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" vault vault "$@"; }
fi

printf "=== 02-pki-internal-ca ===\n"
printf "  External URL : %s\n" "$VAULT_API_ADDR"
printf "  PKI domain   : %s\n" "$VAULT_DOMAIN"

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
  allowed_domains="${VAULT_DOMAIN}" \
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
printf "    vault write pki/issue/server common_name=test.%s ttl=24h\n" "$VAULT_DOMAIN"
