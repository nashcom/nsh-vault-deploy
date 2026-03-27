#!/usr/bin/env bash
# 04-approle-nginx/setup.sh — Create per-server AppRole for NGINX cert delivery
#
# Usage:
#   export VAULT_ADDR=http://127.0.0.1:8100
#   export VAULT_TOKEN=<root-token>
#   bash 04-approle-nginx/setup.sh <server-fqdn>
#
# Example:
#   bash 04-approle-nginx/setup.sh nginx01.example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/../../server/init/vault-init.json}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"

# ── hostname argument ─────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  printf "Usage: %s <server-fqdn>\n" "$0" >&2
  printf "  Example: %s nginx01.example.com\n" "$0" >&2
  exit 1
fi
HOSTNAME="$1"

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

printf "=== 04-approle-nginx: %s ===\n" "$HOSTNAME"

# ── per-server policy ─────────────────────────────────────────────────────────
printf -- "-- Writing policy: nginx-%s --\n" "$HOSTNAME"
printf 'path "secret/data/certs/%s/*" {\n  capabilities = ["read"]\n}\npath "secret/metadata/certs/%s/*" {\n  capabilities = ["read"]\n}\n' \
  "$HOSTNAME" "$HOSTNAME" | vault policy write "nginx-${HOSTNAME}" -

# ── per-server AppRole ────────────────────────────────────────────────────────
printf -- "-- Creating AppRole: nginx-%s --\n" "$HOSTNAME"
vault write "auth/approle/role/nginx-${HOSTNAME}" \
  token_policies="nginx-${HOSTNAME}" \
  token_ttl=2h \
  token_max_ttl=8h \
  secret_id_ttl=0   # non-expiring; rotate manually

ROLE_ID=$(vault read -field=role_id "auth/approle/role/nginx-${HOSTNAME}/role-id")
SECRET_ID=$(vault write -force -field=secret_id "auth/approle/role/nginx-${HOSTNAME}/secret-id")

# ── save credentials ──────────────────────────────────────────────────────────
CREDS_DIR="${SCRIPT_DIR}/credentials/${HOSTNAME}"
mkdir -p "$CREDS_DIR"

printf '%s' "$ROLE_ID"   > "${CREDS_DIR}/role_id"
printf '%s' "$SECRET_ID" > "${CREDS_DIR}/secret_id"
chmod 600 "${CREDS_DIR}/role_id" "${CREDS_DIR}/secret_id"

# ── summary ───────────────────────────────────────────────────────────────────
printf "\n=== 04-approle-nginx complete for %s ===\n" "$HOSTNAME"
printf "  Role ID    : %s\n" "$ROLE_ID"
printf "  Credentials: %s\n" "$CREDS_DIR"
printf "\n"
printf "  Copy to NGINX server:\n"
printf "    scp %s/{role_id,secret_id} root@%s:/etc/vault-agent/\n" "$CREDS_DIR" "$HOSTNAME"
printf "\n"
printf "  Verify:\n"
printf "    vault read auth/approle/role/nginx-%s\n" "$HOSTNAME"
printf "    vault policy read nginx-%s\n" "$HOSTNAME"
