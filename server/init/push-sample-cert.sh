#!/usr/bin/env bash
# push-sample-cert.sh <hostname> [rsa|ecdsa]
#
# Generates a self-signed certificate and pushes it to Vault.
# Used for testing the full pipeline (Vault → agent → NGINX) without a real CA.
# Pushing immediately replaces whatever was there before.
#
# Usage:
#   bash init/push-sample-cert.sh nginx01.example.com ecdsa
#   bash init/push-sample-cert.sh nginx01.example.com rsa
#   bash init/push-sample-cert.sh nginx01.example.com        # default: ecdsa

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> [rsa|ecdsa]}"
CERT_TYPE="${2:-ecdsa}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8100}"   # internal HTTP port
INIT_FILE="./vault-init.json"

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

case "$CERT_TYPE" in
  rsa|ecdsa) ;;
  *) echo "ERROR: cert type must be rsa or ecdsa" >&2; exit 1 ;;
esac

VAULT_PATH="secret/certs/${HOSTNAME}/${CERT_TYPE}"
echo "=== Generating ${CERT_TYPE^^} test certificate for ${HOSTNAME} ==="

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

KEY_PASS=$(openssl rand -base64 18 | tr -d '\n/+')

if [ "$CERT_TYPE" = "ecdsa" ]; then
  openssl ecparam -genkey -name prime256v1 2>/dev/null \
    | openssl ec -aes256 -passout "pass:${KEY_PASS}" \
        -out "${TMPDIR}/server.key.pem" 2>/dev/null
else
  openssl genrsa -aes256 -passout "pass:${KEY_PASS}" \
    -out "${TMPDIR}/server.key.pem" 2048 2>/dev/null
fi

openssl req -new -x509 -days 47 \
  -key    "${TMPDIR}/server.key.pem" \
  -passin "pass:${KEY_PASS}" \
  -out    "${TMPDIR}/server.crt.pem" \
  -subj   "/CN=${HOSTNAME}" \
  -addext "subjectAltName=DNS:${HOSTNAME}" 2>/dev/null

CHAIN=$(cat "${TMPDIR}/server.crt.pem")
ENCRYPTED_KEY=$(cat "${TMPDIR}/server.key.pem")
NOT_AFTER=$(openssl x509 -noout -enddate -in "${TMPDIR}/server.crt.pem" | cut -d= -f2)
SERIAL=$(openssl x509 -noout -serial -in "${TMPDIR}/server.crt.pem" | cut -d= -f2)

echo "=== Pushing to Vault: ${VAULT_PATH} ==="
vault kv put "${VAULT_PATH}" \
  chain="$CHAIN" \
  encrypted_key="$ENCRYPTED_KEY" \
  key_password="$KEY_PASS" \
  cn="$HOSTNAME" \
  cert_type="$CERT_TYPE" \
  serial="$SERIAL" \
  not_after="$NOT_AFTER" \
  pushed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ""
echo "  Vault path:   ${VAULT_PATH}"
echo "  Not after:    ${NOT_AFTER}"
echo "  Serial:       ${SERIAL}"
echo "  Key password: ${KEY_PASS}  (also in Vault)"
echo ""
echo "  Vault Agent will detect the new version and reload NGINX automatically."
