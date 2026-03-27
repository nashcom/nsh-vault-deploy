#!/usr/bin/env bash
# setup.sh — One-time Vault initialization and configuration
#
# Run after first 'docker compose up -d':
#   cd server && bash init/setup.sh
#
# What this does:
#   1. Waits for Vault to be ready
#   2. Initializes Vault (1 key share, threshold 1)
#   3. Unseals Vault
#   4. Enables KV v2 secrets engine at secret/
#   5. Writes certmgr-push policy
#   6. Enables AppRole auth method
#   7. Creates certmgr AppRole and saves credentials
#
# Output files (keep safe, do not commit):
#   vault-init.json      — unseal keys + root token
#   certmgr-approle.env  — role_id and secret_id for CertMgr

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"   # internal HTTP port
INIT_FILE="./vault-init.json"

export VAULT_ADDR

# ── vault CLI: use local binary or fall back to docker exec ───────────────────
if command -v vault >/dev/null 2>&1; then
  vault() { command vault "$@"; }
else
  vault() { docker exec -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="${VAULT_TOKEN:-}" vault vault "$@"; }
fi
export -f vault

# ── wait for Vault ────────────────────────────────────────────────────────────
printf "=== Waiting for Vault API ===\n"
for i in $(seq 1 30); do
  if curl -s --max-time 2 "${VAULT_ADDR}/v1/sys/health" -o /dev/null 2>&1; then
    break
  fi
  printf "  attempt %s/30 — retrying in 2s\n" "$i"
  sleep 2
done

# ── initialize ────────────────────────────────────────────────────────────────
if vault status 2>/dev/null | grep -q "Initialized.*true"; then
  printf "=== Vault already initialized — skipping init ===\n"
  if [ ! -f "$INIT_FILE" ]; then
    printf "ERROR: Vault is initialized but %s is missing.\n" "$INIT_FILE" >&2
    printf "  If this is a fresh setup, run: docker compose down -v && docker compose up -d\n" >&2
    printf "  If you have the unseal keys elsewhere, export VAULT_TOKEN and re-run.\n" >&2
    exit 1
  fi
else
  printf "=== Initializing Vault (1 share, threshold 1) ===\n"
  vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  printf "  Saved to %s — KEEP THIS FILE SAFE, DO NOT COMMIT\n" "$INIT_FILE"
fi

# ── unseal ────────────────────────────────────────────────────────────────────
if vault status 2>/dev/null | grep -q "Sealed.*true"; then
  printf "=== Unsealing Vault ===\n"
  KEY=$(jq -r ".unseal_keys_b64[0]" "$INIT_FILE")
  vault operator unseal "$KEY"
else
  printf "=== Vault already unsealed ===\n"
fi

# ── authenticate as root ──────────────────────────────────────────────────────
VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
export VAULT_TOKEN

# ── secrets engine ────────────────────────────────────────────────────────────
printf "=== Enabling KV v2 at secret/ ===\n"
vault secrets enable -path=secret kv-v2 2>/dev/null \
  && printf "  enabled\n" \
  || printf "  already enabled\n"

# ── policies ──────────────────────────────────────────────────────────────────
printf "=== Writing policies ===\n"
vault policy write certmgr-push - < "$(dirname "$0")/../policies/certmgr-push.hcl"

# ── AppRole auth ──────────────────────────────────────────────────────────────
printf "=== Enabling AppRole auth ===\n"
vault auth enable approle 2>/dev/null \
  && printf "  enabled\n" \
  || printf "  already enabled\n"

# ── certmgr role ──────────────────────────────────────────────────────────────
printf "=== Creating certmgr AppRole ===\n"
vault write auth/approle/role/certmgr \
  token_policies="certmgr-push" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0          # non-expiring secret_id; rotate manually

CERTMGR_ROLE_ID=$(vault read -field=role_id auth/approle/role/certmgr/role-id)
CERTMGR_SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/certmgr/secret-id)

cat > ./certmgr-approle.env <<EOF
VAULT_ADDR=${VAULT_ADDR}
VAULT_ROLE_ID=${CERTMGR_ROLE_ID}
VAULT_SECRET_ID=${CERTMGR_SECRET_ID}
EOF
chmod 600 ./certmgr-approle.env

# ── vault-tls role (for Vault's own TLS cert renewal agent) ──────────────────
printf "=== Writing vault-tls-read policy ===\n"
vault policy write vault-tls-read - < "$(dirname "$0")/../policies/vault-tls-read.hcl"

printf "=== Creating vault-tls AppRole ===\n"
vault write auth/approle/role/vault-tls \
  token_policies="vault-tls-read" \
  token_ttl=2h \
  token_max_ttl=8h \
  secret_id_ttl=0

VAULT_TLS_ROLE_ID=$(vault read -field=role_id auth/approle/role/vault-tls/role-id)
VAULT_TLS_SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/vault-tls/secret-id)

cat > ./vault-tls-approle.env <<EOF
VAULT_TLS_ROLE_ID=${VAULT_TLS_ROLE_ID}
VAULT_TLS_SECRET_ID=${VAULT_TLS_SECRET_ID}
EOF
chmod 600 ./vault-tls-approle.env

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
printf "╔══════════════════════════════════════════════════════════╗\n"
printf "║  Vault setup complete                                    ║\n"
printf "╠══════════════════════════════════════════════════════════╣\n"
printf "║  UI (HTTP loopback): %-36s ║\n" "${VAULT_ADDR}/ui"
printf "║  External TLS:       %-36s ║\n" "https://127.0.0.1:8201"
printf "║  Root token:         %-36s ║\n" "$VAULT_TOKEN"
printf "╠══════════════════════════════════════════════════════════╣\n"
printf "║  Next steps:                                             ║\n"
printf "║  1. push Vault's own TLS cert:                           ║\n"
printf "║     bash init/push-vault-tls.sh vault.example.com        ║\n"
printf "║  2. install Vault Agent on this host:                    ║\n"
printf "║     bash agent/install.sh vault.example.com              ║\n"
printf "║  3. create per-server NGINX roles:                       ║\n"
printf "║     bash init/create-nginx-role.sh nginx01.example.com   ║\n"
printf "╚══════════════════════════════════════════════════════════╝\n"
printf "\n"
printf "  Sensitive files: vault-init.json, certmgr-approle.env, vault-tls-approle.env\n"
printf "  Store vault-init.json offline (unseal keys + root token).\n"
