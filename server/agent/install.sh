#!/usr/bin/env bash
# install.sh <vault-fqdn>
#
# Installs the Vault Agent on the Vault HOST for TLS cert self-management.
# Run as root after setup.sh completes.
#
# Usage:
#   sudo bash server/agent/install.sh vault.example.com

set -euo pipefail

VAULT_FQDN="${1:?Usage: $0 <vault-fqdn>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INIT_DIR="${SCRIPT_DIR}/../init"
CRED_FILE="${INIT_DIR}/vault-tls-approle.env"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root" >&2; exit 1
fi

if [ ! -f "$CRED_FILE" ]; then
  echo "ERROR: ${CRED_FILE} not found — run setup.sh first" >&2; exit 1
fi

# shellcheck source=/dev/null
source "$CRED_FILE"

echo "=== Installing Vault Agent (host TLS manager) for ${VAULT_FQDN} ==="

# ── directories ───────────────────────────────────────────────────────────────
mkdir -p /etc/vault-agent-host/tpl
mkdir -p /etc/vault-agent-host/hooks
mkdir -p /run/vault-agent-host

# ── credentials ───────────────────────────────────────────────────────────────
printf '%s' "$VAULT_TLS_ROLE_ID"   > /etc/vault-agent-host/role_id
printf '%s' "$VAULT_TLS_SECRET_ID" > /etc/vault-agent-host/secret_id
chmod 600 /etc/vault-agent-host/secret_id
echo "  credentials installed"

# ── templates ─────────────────────────────────────────────────────────────────
VAULT_SERVER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
for tpl in vault.crt.tpl vault.key.tpl; do
  sed "s|VAULT_FQDN|${VAULT_FQDN}|g" \
    "${SCRIPT_DIR}/templates/${tpl}" \
    > "/etc/vault-agent-host/tpl/${tpl}"
done
echo "  templates installed"

# ── agent config ──────────────────────────────────────────────────────────────
sed "s|VAULT_SERVER_DIR|${VAULT_SERVER_DIR}|g" \
  "${SCRIPT_DIR}/vault-agent.hcl" \
  > /etc/vault-agent-host/config.hcl
echo "  config installed"

# ── reload hook ───────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/hooks/reload-vault.sh" /etc/vault-agent-host/hooks/
chmod 755 /etc/vault-agent-host/hooks/reload-vault.sh
echo "  hooks installed"

# ── systemd ───────────────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/vault-agent.service" \
  /etc/systemd/system/vault-agent-host.service
systemctl daemon-reload
systemctl enable vault-agent-host.service
systemctl start  vault-agent-host.service
echo "  systemd service enabled and started"

echo ""
echo "=== Done ==="
echo "  Status: systemctl status vault-agent-host"
echo "  Logs:   journalctl -fu vault-agent-host"
