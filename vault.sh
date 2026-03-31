#!/bin/bash
# vault.sh -- run vault CLI commands against the local container
#
# Reads the root token from server/init/vault-init.json automatically.
# Override by exporting VAULT_TOKEN before calling this script.
#
# Usage:
#   ./vault.sh status
#   ./vault.sh secrets list
#   ./vault.sh read pki/config/cluster
#   ./vault.sh write pki/config/acme enabled=true
#   ./vault.sh policy read certmgr-push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_FILE="${SCRIPT_DIR}/server/init/vault-init.json"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"
VAULT_CONTAINER="${VAULT_CONTAINER:-vault}"

if [ -z "${VAULT_TOKEN:-}" ]; then
  if [ -f "$INIT_FILE" ]; then
    VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
  else
    printf "ERROR: VAULT_TOKEN not set and %s not found.\n" "$INIT_FILE" >&2
    printf "  Run server/init/setup.sh first, or: export VAULT_TOKEN=<root-token>\n" >&2
    exit 1
  fi
fi

docker exec -i \
  -e VAULT_ADDR="$VAULT_ADDR" \
  -e VAULT_TOKEN="$VAULT_TOKEN" \
  "$VAULT_CONTAINER" vault "$@"
