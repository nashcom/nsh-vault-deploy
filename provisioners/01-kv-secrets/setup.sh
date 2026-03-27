#!/usr/bin/env bash
# 01-kv-secrets/setup.sh — KV v2 secrets engine + CertMgr AppRole
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100
#   export VAULT_TOKEN=<root-token>
#   bash 01-kv-secrets/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/../../server/init/vault-init.json}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"

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

printf "=== 01-kv-secrets ===\n"

# ── KV v2 secrets engine ──────────────────────────────────────────────────────
printf -- "-- Enabling KV v2 at secret/ --\n"
vault secrets enable -path=secret kv-v2 2>/dev/null \
  && printf "  enabled\n" \
  || printf "  already enabled\n"

# ── certmgr-push policy ───────────────────────────────────────────────────────
printf -- "-- Writing certmgr-push policy --\n"
printf 'path "secret/data/certs/*" {\n  capabilities = ["create", "update", "read"]\n}\npath "secret/metadata/certs/*" {\n  capabilities = ["read", "list", "delete"]\n}\n' \
  | vault policy write certmgr-push -

# ── AppRole auth method ───────────────────────────────────────────────────────
printf -- "-- Enabling AppRole auth --\n"
vault auth enable approle 2>/dev/null \
  && printf "  enabled\n" \
  || printf "  already enabled\n"

# ── certmgr AppRole ───────────────────────────────────────────────────────────
printf -- "-- Creating certmgr AppRole --\n"
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

# ── summary ───────────────────────────────────────────────────────────────────
printf "\n=== 01-kv-secrets complete ===\n"
printf "  certmgr credentials saved to: %s\n" "$OUTPUT_FILE"
printf "\n"
printf "  Verify:\n"
printf "    vault secrets list\n"
printf "    vault auth list\n"
printf "    vault policy read certmgr-push\n"
printf "    vault read auth/approle/role/certmgr\n"
