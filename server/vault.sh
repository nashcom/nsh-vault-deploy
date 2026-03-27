#!/usr/bin/env bash
# server/vault.sh — run vault CLI commands against the local container
#
# Reads the root token from server/init/vault-init.json automatically.
# Override by exporting VAULT_TOKEN before calling this script.
#
# Usage:
#   ./server/vault.sh status
#   ./server/vault.sh secrets list
#   ./server/vault.sh read pki/config/cluster
#   ./server/vault.sh write pki/config/acme enabled=true
#   ./server/vault.sh policy read certmgr-push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${SCRIPT_DIR}/init/vault-init.json"

if [ -z "${VAULT_TOKEN:-}" ]; then
  if [ -f "$INIT_FILE" ]; then
    VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
  else
    printf "ERROR: VAULT_TOKEN not set and %s not found.\n" "$INIT_FILE" >&2
    printf "  Run server/init/setup.sh first, or: export VAULT_TOKEN=<root-token>\n" >&2
    exit 1
  fi
fi

docker exec \
  -e VAULT_ADDR=http://127.0.0.1:8100 \
  -e VAULT_TOKEN="$VAULT_TOKEN" \
  vault vault "$@"
