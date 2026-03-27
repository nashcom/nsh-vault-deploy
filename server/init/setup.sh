#!/usr/bin/env bash
# setup.sh — Vault initialization and unseal
#
# Run once after 'docker compose up -d':
#   cd server && bash init/setup.sh
#
# This script only initializes and unseals Vault.
# All further configuration is done via provisioner scripts
# in the provisioners/ directory.
#
# Output (keep safe, do not commit):
#   init/vault-init.json  — unseal key + root token

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"
INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/vault-init.json}"

export VAULT_ADDR

# ── vault CLI: local binary or docker exec ────────────────────────────────────
if ! command -v vault >/dev/null 2>&1; then
  vault() { docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="${VAULT_TOKEN:-}" vault vault "$@"; }
fi

# ── wait for Vault API ────────────────────────────────────────────────────────
# vault status exit codes: 0=unsealed, 1=error/unreachable, 2=sealed or uninitialized
printf "=== Waiting for Vault ===\n"
for i in $(seq 1 30); do
  vault status >/dev/null 2>&1 || EXIT=$?
  EXIT="${EXIT:-0}"
  if [ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ]; then
    printf "  Vault API ready\n"
    break
  fi
  printf "  attempt %d/30 — retrying in 2s\n" "$i"
  sleep 2
  if [ "$i" -eq 30 ]; then
    printf "ERROR: Vault did not become ready.\n" >&2
    printf "  Check: docker compose logs vault\n" >&2
    exit 1
  fi
done

# ── read status once — vault status exits non-zero when sealed/uninit ─────────
# Use || true so set -e does not kill the script on exit code 2
VAULT_STATUS=$(vault status -format=json 2>/dev/null || true)

# ── initialize ────────────────────────────────────────────────────────────────
INITIALIZED=$(printf '%s' "$VAULT_STATUS" | jq -r '.initialized // "false"')

if [ "$INITIALIZED" = "true" ]; then
  printf "=== Vault already initialized — skipping init ===\n"
  if [ ! -f "$INIT_FILE" ]; then
    printf "ERROR: Vault is initialized but %s is missing.\n" "$INIT_FILE" >&2
    printf "  Restore from backup, or wipe and start fresh:\n" >&2
    printf "    docker compose down -v && docker compose up -d\n" >&2
    exit 1
  fi
else
  printf "=== Initializing Vault (1 share, threshold 1) ===\n"
  vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  printf "  Saved to %s\n" "$INIT_FILE"
  # Refresh status after init
  VAULT_STATUS=$(vault status -format=json 2>/dev/null || true)
fi

# ── unseal ────────────────────────────────────────────────────────────────────
SEALED=$(printf '%s' "$VAULT_STATUS" | jq -r '.sealed // "true"')

if [ "$SEALED" = "true" ]; then
  printf "=== Unsealing Vault ===\n"
  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
  vault operator unseal "$UNSEAL_KEY"
  printf "  Vault unsealed\n"
else
  printf "=== Vault already unsealed ===\n"
fi

# ── done ──────────────────────────────────────────────────────────────────────
ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

printf "\n"
printf "=== Vault is ready ===\n"
printf "  Internal addr : %s\n" "$VAULT_ADDR"
printf "  Root token    : %s\n" "$ROOT_TOKEN"
printf "\n"
printf "  Next steps — run provisioners in order:\n"
printf "    export VAULT_ADDR=%s\n" "$VAULT_ADDR"
printf "    export VAULT_TOKEN=%s\n" "$ROOT_TOKEN"
printf "    cd ../provisioners\n"
printf "    bash 01-kv-secrets/setup.sh\n"
printf "    bash 02-pki-internal-ca/setup.sh\n"
printf "    bash 03-pki-acme/setup.sh\n"
printf "\n"
printf "  KEEP %s SAFE — contains unseal key + root token\n" "$INIT_FILE"
