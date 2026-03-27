#!/usr/bin/env bash
# install.sh <hostname> <vault-addr> [ecdsa|rsa|both]
#
# Deploys Vault Agent + templates to the local machine for NGINX TLS.
# Run as root on the target NGINX server.
#
# Prerequisites:
#   - vault binary installed (/usr/bin/vault)
#   - nginx installed
#   - credentials/ directory populated by server/init/create-nginx-role.sh
#
# Usage:
#   sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200
#   sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200 both

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname> <vault-addr> [ecdsa|rsa|both]}"
VAULT_ADDR="${2:?Usage: $0 <hostname> <vault-addr> [ecdsa|rsa|both]}"
CERT_TYPES="${3:-ecdsa}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRED_DIR="${SCRIPT_DIR}/credentials/${HOSTNAME}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root" >&2; exit 1
fi

if [ ! -f "${CRED_DIR}/role_id" ] || [ ! -f "${CRED_DIR}/secret_id" ]; then
    echo "ERROR: credentials not found in ${CRED_DIR}" >&2
    echo "  Run: bash server/init/create-nginx-role.sh ${HOSTNAME}" >&2
    exit 1
fi

case "$CERT_TYPES" in
    ecdsa|rsa|both) ;;
    *) echo "ERROR: cert types must be ecdsa, rsa, or both" >&2; exit 1 ;;
esac

echo "=== Installing Vault Agent for ${HOSTNAME} (${CERT_TYPES}) ==="

# ── directories ───────────────────────────────────────────────────────────────
mkdir -p /etc/vault-agent/tpl/ecdsa
mkdir -p /etc/vault-agent/tpl/rsa
mkdir -p /etc/vault-agent/hooks
mkdir -p /run/vault-agent

# ── credentials ───────────────────────────────────────────────────────────────
cp "${CRED_DIR}/role_id"   /etc/vault-agent/role_id
cp "${CRED_DIR}/secret_id" /etc/vault-agent/secret_id
chmod 600 /etc/vault-agent/secret_id
echo "  credentials installed"

# ── templates ─────────────────────────────────────────────────────────────────
for ct in ecdsa rsa; do
    for tpl in server.crt.tpl server.key.tpl ssl_password.tpl; do
        sed "s|SERVER_HOSTNAME|${HOSTNAME}|g" \
            "${SCRIPT_DIR}/templates/${ct}/${tpl}" \
            > "/etc/vault-agent/tpl/${ct}/${tpl}"
    done
done
echo "  templates installed"

# ── agent config ──────────────────────────────────────────────────────────────
# Build the config from the template, then uncomment RSA section if needed
sed -e "s|VAULT_ADDR|${VAULT_ADDR}|g" \
    -e "s|SERVER_HOSTNAME|${HOSTNAME}|g" \
    "${SCRIPT_DIR}/vault-agent.hcl.tpl" \
    > /etc/vault-agent/config.hcl

if [ "$CERT_TYPES" = "rsa" ]; then
    # RSA only: comment out ECDSA section, uncomment RSA section
    sed -i \
        -e '/── ECDSA/,/── RSA/{ /^template/,/^}$/s/^/# / }' \
        /etc/vault-agent/config.hcl
    sed -i 's/^# \(template\|  \|}\)/\1/' /etc/vault-agent/config.hcl
elif [ "$CERT_TYPES" = "both" ]; then
    # Both: uncomment RSA section
    sed -i 's/^# \(template\|  \|}\)/\1/' /etc/vault-agent/config.hcl
fi
echo "  config written to /etc/vault-agent/config.hcl"

# ── hooks ─────────────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/hooks/reload-nginx.sh" /etc/vault-agent/hooks/
chmod 755 /etc/vault-agent/hooks/reload-nginx.sh
echo "  hooks installed"

# ── systemd service ───────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/vault-agent.service" /etc/systemd/system/vault-agent-nginx.service
systemctl daemon-reload
systemctl enable vault-agent-nginx.service
systemctl start  vault-agent-nginx.service
echo "  systemd service enabled and started"

# ── nginx config example ──────────────────────────────────────────────────────
sed -e "s|SERVER_HOSTNAME|${HOSTNAME}|g" \
    -e "s|CERT_TYPES|${CERT_TYPES}|g" \
    "${SCRIPT_DIR}/nginx-ssl.conf.example" \
    > /etc/vault-agent/nginx-ssl.conf.example

echo ""
echo "=== Done ==="
echo "  Status:   systemctl status vault-agent-nginx"
echo "  Logs:     journalctl -fu vault-agent-nginx"
echo "  Files:    ls -la /run/vault/ssl/"
echo "  Example:  /etc/vault-agent/nginx-ssl.conf.example"
