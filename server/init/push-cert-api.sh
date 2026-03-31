#!/usr/bin/env bash
# push-cert-api.sh <hostname> [ecdsa|rsa]
#
# Pushes a certificate to Vault using the REST API directly — no vault CLI binary.
# This mirrors exactly what CertMgr's servertask does from memory.
#
# Two API calls:
#   POST /v1/auth/approle/login          → client token
#   POST /v1/secret/data/certs/<fqdn>/<type>  → write secret
#
# Usage:
#   bash init/push-cert-api.sh nginx01.example.com ecdsa

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> [ecdsa|rsa]}"
CERT_TYPE="${2:-ecdsa}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
INIT_FILE="./vault-init.json"
CRED_DIR="$(dirname "$0")/../../client/nginx/credentials/${HOSTNAME}"

# ── credentials ───────────────────────────────────────────────────────────────
# For testing: read from the credential files created by create-nginx-role.sh
# In CertMgr: role_id and secret_id come from memory, never from disk
if [ ! -f "${CRED_DIR}/role_id" ]; then
    echo "ERROR: no credentials for ${HOSTNAME}" >&2
    echo "  Run: bash init/create-nginx-role.sh ${HOSTNAME}" >&2
    exit 1
fi

ROLE_ID=$(cat "${CRED_DIR}/role_id")
SECRET_ID=$(cat "${CRED_DIR}/secret_id")

# ── generate test cert material (stand-in for CertMgr's ACME output) ─────────
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
    -key "${TMPDIR}/server.key.pem" -passin "pass:${KEY_PASS}" \
    -out "${TMPDIR}/server.crt.pem" \
    -subj "/CN=${HOSTNAME}" -addext "subjectAltName=DNS:${HOSTNAME}" 2>/dev/null

CHAIN=$(cat "${TMPDIR}/server.crt.pem")
ENCRYPTED_KEY=$(cat "${TMPDIR}/server.key.pem")
NOT_AFTER=$(openssl x509 -noout -enddate -in "${TMPDIR}/server.crt.pem" | cut -d= -f2)
SERIAL=$(openssl x509 -noout -serial  -in "${TMPDIR}/server.crt.pem" | cut -d= -f2)

# ── Step 1: AppRole login → client token ─────────────────────────────────────
echo "=== Step 1: AppRole login ==="
echo "  POST ${VAULT_ADDR}/v1/auth/approle/login"

LOGIN_RESPONSE=$(curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    "${VAULT_ADDR}/v1/auth/approle/login" \
    -d "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}")

CLIENT_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.auth.client_token')
TOKEN_TTL=$(echo    "$LOGIN_RESPONSE" | jq -r '.auth.lease_duration')

echo "  token TTL: ${TOKEN_TTL}s"

# ── Step 2: write secret from memory ─────────────────────────────────────────
VAULT_PATH="secret/data/certs/${HOSTNAME}/${CERT_TYPE}"
echo ""
echo "=== Step 2: push cert ==="
echo "  POST ${VAULT_ADDR}/v1/${VAULT_PATH}"

# Build JSON payload — in CertMgr this is built from in-memory buffers (cJSON)
PAYLOAD=$(jq -nc \
    --arg chain        "$CHAIN"        \
    --arg encrypted_key "$ENCRYPTED_KEY" \
    --arg key_password "$KEY_PASS"     \
    --arg cert_type    "$CERT_TYPE"    \
    --arg serial       "$SERIAL"       \
    --arg not_after    "$NOT_AFTER"    \
    --arg pushed_at    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{data: {chain: $chain, encrypted_key: $encrypted_key,
             key_password: $key_password, cert_type: $cert_type,
             serial: $serial, not_after: $not_after, pushed_at: $pushed_at}}')

WRITE_RESPONSE=$(curl -sf \
    -X POST \
    -H "X-Vault-Token: ${CLIENT_TOKEN}" \
    -H "Content-Type: application/json" \
    "${VAULT_ADDR}/v1/${VAULT_PATH}" \
    -d "$PAYLOAD")

VERSION=$(echo "$WRITE_RESPONSE" | jq -r '.data.version')

echo "  version: ${VERSION}"
echo "  serial:  ${SERIAL}"
echo "  expires: ${NOT_AFTER}"
echo ""
echo "  Vault Agent will detect version ${VERSION} and reload NGINX."

# Zero the token — in CertMgr this is memset()
unset CLIENT_TOKEN
