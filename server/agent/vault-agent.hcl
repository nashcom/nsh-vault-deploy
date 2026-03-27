# Vault Agent — running on the Vault HOST
# Manages Vault's own external TLS certificate.
#
# Connects to the loopback HTTP listener (127.0.0.1:8200) — no TLS needed.
# Watches secret/certs/<vault-fqdn>/tls for a new cert version.
# Writes cert + key to ./tls/ (volume-mounted into the Vault container).
# Sends SIGHUP to the Vault container to reload the cert without restart.
#
# To use the loopback mTLS option (Option B in vault.hcl) instead,
# uncomment the tls_* lines in the vault block below.

vault {
  address = "http://127.0.0.1:8200"

  # Option B — mTLS on loopback (uncomment if using Option B in vault.hcl)
  # address        = "https://127.0.0.1:8200"
  # ca_cert        = "/etc/vault-agent/tls/loopback-ca.crt"
  # client_cert    = "/etc/vault-agent/tls/agent-client.crt"
  # client_key     = "/etc/vault-agent/tls/agent-client.key"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/etc/vault-agent/role_id"
      secret_id_file_path = "/etc/vault-agent/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/run/vault-agent-host/token"
      mode = "0600"
    }
  }
}

# Certificate chain — written to the tls/ directory that is volume-mounted
# into the Vault container as /vault/tls (read-only inside the container)
template {
  source      = "/etc/vault-agent/tpl/vault.crt.tpl"
  destination = "VAULT_SERVER_DIR/tls/vault.crt"
  command     = "VAULT_SERVER_DIR/agent/hooks/reload-vault.sh"
}

template {
  source      = "/etc/vault-agent/tpl/vault.key.tpl"
  destination = "VAULT_SERVER_DIR/tls/vault.key"
  perms       = "0600"
}
