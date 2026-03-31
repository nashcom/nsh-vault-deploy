#!/usr/bin/env bash
# reload-nginx.sh
# Called by Vault Agent after any cert template renders.
# Checks which cert types are configured, verifies all files for each type
# are present, validates nginx config, then reloads.

set -euo pipefail

SSL_DIR="/run/vault/ssl"
LOG_TAG="vault-agent-nginx"

log() { echo "[$LOG_TAG] $*" | tee -a /var/log/vault-agent-nginx.log; }
err() { echo "[$LOG_TAG] ERROR: $*" >&2 | tee -a /var/log/vault-agent-nginx.log; }

# Check each cert type directory that exists
all_ready=true
for ct in ecdsa rsa; do
  dir="${SSL_DIR}/${ct}"
  [ -d "$dir" ] || continue   # skip cert types not configured

  for f in "${dir}/server.crt" "${dir}/server.key" "${dir}/ssl_password"; do
    if [ ! -f "$f" ]; then
      log "Waiting: $f not yet rendered — skipping reload"
      all_ready=false
    fi
  done
done

$all_ready || exit 0

# Validate NGINX config before reloading
if ! nginx -t 2>/tmp/nginx-test.out; then
  err "nginx config test failed — aborting reload"
  cat /tmp/nginx-test.out >&2
  exit 1
fi

nginx -s reload
log "nginx reloaded with new certificate"
