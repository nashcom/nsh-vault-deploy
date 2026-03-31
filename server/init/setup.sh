#!/bin/bash
# setup.sh -- Vault initialization and unseal
#
# Run once after 'docker compose up -d':
#   cd server && bash init/setup.sh
#
# This script only initializes and unseals Vault.
# All further configuration is done via provisioner scripts
# in the provisioners/ directory.
#
# Output (keep safe, do not commit):
#   init/vault-init.json  -- unseal key + root token

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../script_lib.sh"

INIT_FILE="${INIT_FILE:-${SCRIPT_DIR}/vault-init.json}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"
VAULT_CONTAINER="${VAULT_CONTAINER:-vault}"

export VAULT_ADDR


header "Waiting for Vault"

# vault status exit codes: 0=unsealed, 1=error/unreachable, 2=sealed or uninitialized
for i in $(seq 1 30); do
  EXIT=0
  docker exec -e VAULT_ADDR="$VAULT_ADDR" "$VAULT_CONTAINER" vault status >/dev/null 2>&1 || EXIT=$?
  if [ "$EXIT" -eq 0 ] || [ "$EXIT" -eq 2 ]; then
    echo "  Vault API ready"
    break
  fi
  printf "  attempt %d/30 -- retrying in 2s\n" "$i"
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Vault did not become ready." >&2
    echo "  Check: docker compose logs vault" >&2
    exit 1
  fi
done

# Use || true so set -e does not kill the script on exit code 2
VAULT_STATUS=$(docker exec -e VAULT_ADDR="$VAULT_ADDR" "$VAULT_CONTAINER" vault status -format=json 2>/dev/null || true)


header "Initializing Vault"

INITIALIZED=$(printf '%s' "$VAULT_STATUS" | jq -r '.initialized // "false"')

if [ "$INITIALIZED" = "true" ]; then
  echo "  already initialized -- skipping"
  if [ ! -f "$INIT_FILE" ]; then
    echo "ERROR: Vault is initialized but $INIT_FILE is missing." >&2
    echo "  Restore from backup, or wipe and start fresh:" >&2
    echo "    docker compose down -v && docker compose up -d" >&2
    exit 1
  fi
else
  echo "  initializing (1 share, threshold 1)"
  docker exec -e VAULT_ADDR="$VAULT_ADDR" "$VAULT_CONTAINER" vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  echo "  saved to $INIT_FILE"
  VAULT_STATUS=$(docker exec -e VAULT_ADDR="$VAULT_ADDR" "$VAULT_CONTAINER" vault status -format=json 2>/dev/null || true)
fi


header "Unsealing Vault"

SEALED=$(printf '%s' "$VAULT_STATUS" | jq -r '.sealed // "true"')

if [ "$SEALED" = "true" ]; then
  UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' "$INIT_FILE")
  docker exec -e VAULT_ADDR="$VAULT_ADDR" "$VAULT_CONTAINER" vault operator unseal "$UNSEAL_KEY" >/dev/null
  echo "  unsealed"
else
  echo "  already unsealed"
fi


ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")

log "Vault is ready"

echo "  Internal addr : $VAULT_ADDR"
echo "  Root token    : $ROOT_TOKEN"
echo
echo "  Next steps -- run provisioners in order:"
echo "    cd ../provisioners"
echo "    bash 01-kv-secrets/setup.sh"
echo "    bash 02-pki-internal-ca/setup.sh"
echo "    bash 03-pki-intermediate-ca/setup.sh"
echo "    bash 04-pki-acme/setup.sh"
echo "    bash 05-approle-nginx/setup.sh <server-fqdn>"
echo "    bash 06-mtls-bootstrap/setup.sh"
echo "    bash 07-pki-certmgr/setup.sh"
echo
echo "  KEEP $INIT_FILE SAFE -- contains unseal key + root token"
