#!/usr/bin/env bash
# 03-pki-acme/setup.sh — Enable ACME protocol on the PKI secrets engine
#
# Requires: 02-pki-internal-ca completed (pki/ engine must exist)
# Requires: Vault 1.14+
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100
#   export VAULT_TOKEN=<root-token>
#   export VAULT_API_ADDR=https://vault.example.com
#   bash 03-pki-acme/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/../../server/init/vault-init.json}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"

# ── public URL written into ACME cluster configuration ───────────────────────
# VAULT_ADDR (local) is used to connect and run commands.
# VAULT_API_ADDR is different: it gets stored inside Vault as the base URL for
# all ACME endpoints (directory, new-nonce, new-order, etc.).
# ACME clients fetch those URLs directly — it must be your public address.
if [ -z "${VAULT_API_ADDR:-}" ]; then
  printf "ERROR: VAULT_API_ADDR is required — set it to the public URL of this Vault server.\n" >&2
  printf "  This is not your connection address. It gets written into Vault's ACME config.\n" >&2
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

printf "=== 03-pki-acme ===\n"
printf "  External URL : %s\n" "$VAULT_API_ADDR"
printf "  ACME directory will be at:\n"
printf "    %s/v1/pki/acme/directory\n" "$VAULT_API_ADDR"

# ── check PKI engine exists ───────────────────────────────────────────────────
if ! vault secrets list -format=json | jq -e '."pki/"' >/dev/null 2>&1; then
  printf "ERROR: PKI secrets engine not found.\n" >&2
  printf "  Run 02-pki-internal-ca/setup.sh first.\n" >&2
  exit 1
fi

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
  allowed_domains="example.com" \
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
printf "      -d test.example.com --standalone\n"
printf "\n"
printf "  Issue with certbot:\n"
printf "    certbot certonly --server %s/v1/pki/acme/directory \\\\\n" "$VAULT_API_ADDR"
printf "      --standalone -d test.example.com\n"
