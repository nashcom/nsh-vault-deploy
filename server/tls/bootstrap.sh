#!/usr/bin/env bash
# bootstrap.sh [--loopback] [fqdn]
#
# Generates the initial self-signed TLS certificate for Vault.
# Run once before first 'docker compose up'.
#
# After Vault is running, CertMgr takes over cert renewal automatically.
# The bootstrap cert is only used until the first CertMgr push.
#
# Usage:
#   bash tls/bootstrap.sh                              # external cert only
#   bash tls/bootstrap.sh vault.example.com           # with real FQDN
#   bash tls/bootstrap.sh --loopback                  # also generate loopback cert
#   bash tls/bootstrap.sh --loopback vault.example.com

set -euo pipefail

LOOPBACK=false
FQDN="vault.local"

for arg in "$@"; do
  case "$arg" in
    --loopback) LOOPBACK=true ;;
    *)          FQDN="$arg"   ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── external cert (vault.crt / vault.key) ─────────────────────────────────────
echo "=== Generating bootstrap cert for ${FQDN} ==="

openssl req -x509 -newkey ec \
  -pkeyopt ec_paramgen_curve:P-256 \
  -days 365 -nodes \
  -keyout "${SCRIPT_DIR}/vault.key" \
  -out    "${SCRIPT_DIR}/vault.crt" \
  -subj   "/CN=${FQDN}/O=vault-bootstrap" \
  -addext "subjectAltName=DNS:${FQDN},DNS:localhost,IP:127.0.0.1" \
  2>/dev/null

chmod 644 "${SCRIPT_DIR}/vault.key"   # world-readable so Docker uid 1000 can read it
echo "  ${SCRIPT_DIR}/vault.crt"
echo "  ${SCRIPT_DIR}/vault.key"

# ── loopback cert (optional — for mTLS on 127.0.0.1:8200) ────────────────────
if [ "$LOOPBACK" = "true" ]; then
  echo ""
  echo "=== Generating loopback self-signed cert (mTLS option) ==="

  # CA key + cert
  openssl req -x509 -newkey ec \
    -pkeyopt ec_paramgen_curve:P-256 \
    -days 3650 -nodes \
    -keyout "${SCRIPT_DIR}/loopback-ca.key" \
    -out    "${SCRIPT_DIR}/loopback-ca.crt" \
    -subj   "/CN=vault-loopback-ca/O=vault-internal" \
    2>/dev/null
  chmod 644 "${SCRIPT_DIR}/loopback-ca.key"

  # Server cert signed by loopback CA
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "${SCRIPT_DIR}/loopback.key" \
    -out    "${SCRIPT_DIR}/loopback.csr" \
    -subj   "/CN=127.0.0.1/O=vault-internal" \
    2>/dev/null
  openssl x509 -req -days 3650 \
    -in    "${SCRIPT_DIR}/loopback.csr" \
    -CA    "${SCRIPT_DIR}/loopback-ca.crt" \
    -CAkey "${SCRIPT_DIR}/loopback-ca.key" \
    -CAcreateserial \
    -out   "${SCRIPT_DIR}/loopback.crt" \
    -extfile <(echo "subjectAltName=IP:127.0.0.1,DNS:localhost") \
    2>/dev/null
  chmod 644 "${SCRIPT_DIR}/loopback.key"
  rm -f "${SCRIPT_DIR}/loopback.csr"

  # Client cert for Vault Agent (mTLS)
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "${SCRIPT_DIR}/agent-client.key" \
    -out    "${SCRIPT_DIR}/agent-client.csr" \
    -subj   "/CN=vault-agent/O=vault-internal" \
    2>/dev/null
  openssl x509 -req -days 3650 \
    -in    "${SCRIPT_DIR}/agent-client.csr" \
    -CA    "${SCRIPT_DIR}/loopback-ca.crt" \
    -CAkey "${SCRIPT_DIR}/loopback-ca.key" \
    -CAcreateserial \
    -out   "${SCRIPT_DIR}/agent-client.crt" \
    2>/dev/null
  chmod 644 "${SCRIPT_DIR}/agent-client.key"
  rm -f "${SCRIPT_DIR}/agent-client.csr"

  echo "  ${SCRIPT_DIR}/loopback.crt / loopback.key  (server)"
  echo "  ${SCRIPT_DIR}/loopback-ca.crt              (CA — distribute to agents)"
  echo "  ${SCRIPT_DIR}/agent-client.crt / .key      (client cert for Vault Agent)"
  echo ""
  echo "  To enable: uncomment Option B in config/vault.hcl"
  echo "  Update agent config: vault { tls_ca_cert + client_cert + client_key }"
fi

echo ""
echo "=== Done. Start Vault: docker compose up -d ==="
echo ""
echo "  Bootstrap cert expires in 365 days."
echo "  CertMgr will replace it automatically after first push."
