#!/bin/bash
# 06-mtls-bootstrap/enroll.sh -- Per-server enrollment: policy + cert auth role + wrap token
#
# Usage:
#   bash enroll.sh <server-fqdn>
#
# Example:
#   bash enroll.sh server01.example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../script_lib.sh"

INIT_FILE="${SCRIPT_DIR}/../../../server/init/vault-init.json"

LoadVaultToken "$INIT_FILE"

header "06-mtls-bootstrap Enrollment Configuration"

GetInput VAULT_ADDR  "Vault address"
GetInput VAULT_TOKEN "Vault root token"

FQDN="${1:-}"
GetInput FQDN "Server FQDN (e.g. server01.example.com)"

WRAP_TTL="${WRAP_TTL:-24h}"
CERT_TTL="${CERT_TTL:-2160h}"

export VAULT_ADDR VAULT_TOKEN

SetupVaultCLI

echo "  Server FQDN : $FQDN"
echo "  Wrap TTL    : $WRAP_TTL"
echo "  Cert TTL    : $CERT_TTL"


header "Writing policy: srvguard-${FQDN}"

sed "s/SERVER_HOSTNAME/${FQDN}/g" "$SCRIPT_DIR/nginx-read.hcl.tpl" \
  | vault policy write "srvguard-${FQDN}" -


header "Reading PKI CA cert"

CA_CERT=$(vault read -field=certificate pki/cert/ca)


header "Creating cert auth role: srvguard-${FQDN}"

vault write "auth/cert/certs/srvguard-${FQDN}" \
  display_name="srvguard-${FQDN}" \
  certificate="${CA_CERT}" \
  allowed_common_names="${FQDN}" \
  token_policies="srvguard-${FQDN}" \
  token_ttl=1h \
  token_max_ttl=4h


header "Issuing client cert (wrap-ttl=${WRAP_TTL})"

WRAP_RESPONSE=$(vault write \
  -wrap-ttl="${WRAP_TTL}" \
  -format=json \
  pki/issue/srvguard-client \
  common_name="${FQDN}" \
  ttl="${CERT_TTL}")

WRAP_TOKEN=$(printf '%s' "$WRAP_RESPONSE" | jq -r '.wrap_info.token')

CREDS_DIR="${SCRIPT_DIR}/credentials/${FQDN}"
mkdir -p "$CREDS_DIR"
printf '%s' "$WRAP_TOKEN" > "${CREDS_DIR}/wrap_token"
chmod 600 "${CREDS_DIR}/wrap_token"


log "Enrollment complete: $FQDN"

echo "  Wrap token : credentials/${FQDN}/wrap_token"
echo "  Wrap TTL   : $WRAP_TTL -- deploy before it expires"
echo
echo "  Deploy:"
echo "    scp credentials/${FQDN}/wrap_token root@${FQDN}:/etc/srvguard/wrap_token"
echo
echo "  srvguard will bootstrap on next start:"
echo "    - Unwraps the token to get the client cert+key"
echo "    - Encrypts with machine-id key -> /etc/srvguard/client.enc"
echo "    - Deletes wrap_token -- never needed again unless trust is lost"
echo
echo "  Re-enrollment (lost trust only):"
echo "    bash enroll.sh ${FQDN}   # issue new wrap token"
echo "    scp credentials/${FQDN}/wrap_token root@${FQDN}:/etc/srvguard/wrap_token"
