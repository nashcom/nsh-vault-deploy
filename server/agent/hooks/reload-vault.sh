#!/usr/bin/env bash
# reload-vault.sh
# Called by Vault Agent after vault.crt is written.
# Sends SIGHUP to the Vault container — reloads TLS cert without restart.
# Active connections are not interrupted; new connections use the new cert.

set -euo pipefail

LOG_TAG="vault-agent-host"
log() { echo "[$LOG_TAG] $*" | tee -a /var/log/vault-agent-host.log; }
err() { echo "[$LOG_TAG] ERROR: $*" >&2 | tee -a /var/log/vault-agent-host.log; }

TLS_DIR="$(dirname "$0")/../../tls"

# Both files must be present before reloading
for f in "${TLS_DIR}/vault.crt" "${TLS_DIR}/vault.key"; do
  if [ ! -f "$f" ]; then
    log "Waiting: $f not yet rendered — skipping reload"
    exit 0
  fi
done

# Send SIGHUP to the vault container — triggers TLS cert reload
if docker kill --signal=HUP vault 2>/dev/null; then
  log "SIGHUP sent to vault container — TLS cert reloaded"
else
  err "docker kill failed — is the vault container running?"
  exit 1
fi
