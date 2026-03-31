# Vault server configuration
#
# External address is set via environment variables in docker-compose / .env:
#   VAULT_API_ADDR     — public HTTPS URL, e.g. https://vault.example.com
#   VAULT_CLUSTER_ADDR — internal cluster URL (set automatically by docker-compose)

ui            = true
disable_mlock = true   # required inside containers

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"
}

# ── Internal listener — HTTP, Docker network only ─────────────────────────────
# Port 8100 is published to localhost only.
# Used by setup scripts, health checks, and admin operations.
listener "tcp" {
  address     = "0.0.0.0:8100"
  tls_disable = "true"
}

# ── External listener — TLS ───────────────────────────────────────────────────
# Port 8200 inside the container. Map to 443 in docker-compose for standard HTTPS.
# Certificate: server/tls/vault.crt + vault.key
# Bootstrap: run tls/bootstrap.sh <fqdn> before first start.
listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_cert_file   = "/vault/tls/vault.crt"
  tls_key_file    = "/vault/tls/vault.key"
  tls_min_version = "tls12"

  # ── mTLS client authentication ───────────────────────────────────────────────
  # Required for srvguard and other services to authenticate via client certificate.
  # Without tls_client_ca_file, Vault does not request a client cert during the
  # TLS handshake and cert auth cannot work regardless of how it is configured.
  #
  # Steps to enable:
  #   1. Run provisioner 02-pki-internal-ca to create the internal CA
  #   2. Run provisioner 06-mtls-bootstrap/setup.sh — it writes client-ca.crt here
  #   3. Uncomment below and run: vault operator reload
  #
  # tls_client_ca_file                 = "/vault/tls/client-ca.crt"
  # tls_require_and_verify_client_cert = false   # false = optional, UI and CLI still work
}

# api_addr and cluster_addr are provided via VAULT_API_ADDR / VAULT_CLUSTER_ADDR
# environment variables — see server/.env.example.

default_lease_ttl = "168h"
max_lease_ttl     = "8760h"   # 1 year — needed for PKI root CA
