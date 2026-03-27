# Vault server configuration

ui            = true
disable_mlock = true   # required inside containers

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

# ── Internal listener — HTTP, Docker network only ─────────────────────────────
# Port 8201 is NOT published in docker-compose.
# Only reachable from containers in the same Docker network
# (vault-agent sidecar, healthcheck, docker exec).
listener "tcp" {
  address     = "0.0.0.0:8100"
  tls_disable = "true"
}

# ── External listener — TLS, standard Vault port ──────────────────────────────
# Port 8200 is published in docker-compose.
# Certificate managed by vault-agent sidecar:
#   first boot : bootstrap self-signed cert (tls/bootstrap.sh)
#   after init : CertMgr pushes real cert → agent writes → vault operator reload
listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_cert_file   = "/vault/tls/vault.crt"
  tls_key_file    = "/vault/tls/vault.key"
  tls_min_version = "tls12"
}

api_addr     = "https://127.0.0.1:8200"   # override with real FQDN in production
cluster_addr = "https://127.0.0.1:8202"

default_lease_ttl = "168h"
max_lease_ttl     = "720h"
