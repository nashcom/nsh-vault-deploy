#!/usr/bin/env bash
# 03-pki-acme/setup.sh — Enable ACME protocol on the PKI secrets engine
#
# Requires: 02-pki-internal-ca completed (pki/ engine must exist)
# Requires: Vault 1.14+
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100           # local connection (always)
#   export VAULT_TOKEN=<root-token>
#   export VAULT_API_ADDR=https://vault.example.com   # public URL — written into ACME config
#   export VAULT_DOMAIN=example.com                   # domain for ACME role
#   bash 03-pki-acme/setup.sh

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

printf "  VAULT_API_ADDR — public URL written INTO Vault config (base URL for all ACME endpoints)\n"
printf "                   ACME clients redirect to this URL — must be externally reachable\n"
ask VAULT_API_ADDR "Public Vault URL (e.g. https://vault.example.com)"

printf "  VAULT_DOMAIN   — domain for which ACME clients may request certificates\n"
ask VAULT_DOMAIN "Certificate domain (e.g. example.com)"

export VAULT_ADDR VAULT_TOKEN

# ── vault CLI wrapper ─────────────────────────────────────────────────────────
if ! command -v vault >/dev/null 2>&1; then
  vault() { docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" vault vault "$@"; }
fi

printf "=== 03-pki-acme ===\n"
printf "  External URL : %s\n" "$VAULT_API_ADDR"
printf "  PKI domain   : %s\n" "$VAULT_DOMAIN"
printf "  ACME directory will be at:\n"
printf "    %s/v1/pki/acme/directory\n" "$VAULT_API_ADDR"

# ── check PKI engine exists ───────────────────────────────────────────────────
if ! vault secrets list -format=json | jq -e '."pki/"' >/dev/null 2>&1; then
  printf "ERROR: PKI secrets engine not found.\n" >&2
  printf "  Run 02-pki-internal-ca/setup.sh first.\n" >&2
  exit 1
fi

# ── tune PKI mount for ACME response headers ─────────────────────────────────
# Vault filters non-standard response headers by default.
# Replay-Nonce is required: ACME clients use it to prevent replay attacks.
# Link is required: ACME responses include Link headers for ToS and chain URLs.
# Without this tuning, the nonce endpoint returns 200 with no Replay-Nonce header
# and all ACME clients silently fail to get a nonce.
printf -- "-- Tuning PKI mount: allowing ACME response headers --\n"
vault secrets tune \
  -allowed-response-headers="Replay-Nonce" \
  -allowed-response-headers="Link" \
  -allowed-response-headers="Location" \
  pki

# ── configure cluster path ────────────────────────────────────────────────────
# This is the base URL Vault uses to build all ACME endpoint URLs.
# It MUST match the external address — ACME clients redirect to these URLs.
printf -- "-- Configuring PKI cluster path --\n"
vault write pki/config/cluster \
  path="${VAULT_API_ADDR}/v1/pki"

# ── enable ACME ───────────────────────────────────────────────────────────────
printf -- "-- Enabling ACME on pki/ --\n"
vault write pki/config/acme \
  enabled=true \
  default_directory_policy="sign-verbatim"

# sign-verbatim: ACME clients can request any domain (no role restrictions).
# For production, change to: default_directory_policy="role:acme"
# and ensure the 'acme' role's allowed_domains matches your needs.

# ── create ACME role ──────────────────────────────────────────────────────────
printf -- "-- Creating role: acme --\n"
vault write pki/roles/acme \
  allowed_domains="${VAULT_DOMAIN}" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_wildcard_certificates=false \
  max_ttl=2160h \
  key_type=any \
  require_cn=false \
  no_store=false \
  allow_ip_sans=false

# ── summary ───────────────────────────────────────────────────────────────────
printf "\n=== 03-pki-acme complete ===\n"
printf "  ACME directory : %s/v1/pki/acme/directory\n" "$VAULT_API_ADDR"
printf "\n"
printf "  Verify:\n"
printf "    vault read pki/config/acme\n"
printf "    vault read pki/config/cluster\n"
printf "    curl -s %s/v1/pki/acme/directory | jq .\n" "$VAULT_API_ADDR"
printf "\n"
printf "  Issue with acme.sh:\n"
printf "    acme.sh --issue --server %s/v1/pki/acme/directory \\\\\n" "$VAULT_API_ADDR"
printf "      -d test.%s --standalone\n" "$VAULT_DOMAIN"
printf "\n"
printf "  Issue with certbot:\n"
printf "    certbot certonly --server %s/v1/pki/acme/directory \\\\\n" "$VAULT_API_ADDR"
printf "      --standalone -d test.%s\n" "$VAULT_DOMAIN"
