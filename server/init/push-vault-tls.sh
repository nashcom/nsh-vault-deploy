#!/usr/bin/env bash
# push-vault-tls.sh [fqdn]
#
# Pushes Vault's own TLS certificate to Vault.
# After this, the Vault Agent on the Vault host will pick it up,
# write it to tls/, and send SIGHUP to reload — no manual steps.
#
# Vault's TLS secret uses 'key' (unencrypted) not 'encrypted_key + key_password'
# because Vault reads the key directly — it has no ssl_password_file mechanism.
# Protection is Vault's own access controls.
#
# Usage:
#   bash init/push-vault-tls.sh                    # uses existing tls/vault.crt
#   bash init/push-vault-tls.sh vault.example.com  # generate new self-signed

set -euo pipefail

FQDN="${1:-vault.local}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"   # internal HTTP port
INIT_FILE="./vault-init.json"
TLS_DIR="./tls"

export VAULT_ADDR

if command -v vault >/dev/null 2>&1; then
  vault() { command vault "$@"; }
else
  vault() { docker exec -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="${VAULT_TOKEN:-}" vault vault "$@"; }
fi
export -f vault

if [ -z "${VAULT_TOKEN:-}" ]; then
  VAULT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
  export VAULT_TOKEN
fi

VAULT_PATH="secret/certs/${FQDN}/tls"

if [ ! -f "${TLS_DIR}/vault.crt" ] || [ ! -f "${TLS_DIR}/vault.key" ]; then
  echo "=== No cert found — generating bootstrap self-signed cert ==="
  bash "${TLS_DIR}/bootstrap.sh" "$FQDN"
fi

CHAIN=$(cat "${TLS_DIR}/vault.crt")
KEY=$(cat "${TLS_DIR}/vault.key")
NOT_AFTER=$(openssl x509 -noout -enddate -in "${TLS_DIR}/vault.crt" | cut -d= -f2)
SERIAL=$(openssl x509 -noout -serial  -in "${TLS_DIR}/vault.crt" | cut -d= -f2)

echo "=== Pushing Vault TLS cert to ${VAULT_PATH} ==="
vault kv put "${VAULT_PATH}" \
  chain="$CHAIN" \
  key="$KEY" \
  cn="$FQDN" \
  cert_type="tls" \
  serial="$SERIAL" \
  not_after="$NOT_AFTER" \
  pushed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ""
echo "  Vault Agent on this host will detect the new version"
echo "  and reload the external TLS listener automatically."
echo ""
echo "  To verify: vault kv get ${VAULT_PATH}"
