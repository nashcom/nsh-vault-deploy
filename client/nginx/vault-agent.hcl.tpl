# Vault Agent configuration for NGINX TLS certificate delivery
#
# Deploy to: /etc/vault-agent/config.hcl
# Replace before deploying:
#   VAULT_ADDR       — e.g. https://vault.example.com:8200
#   SERVER_HOSTNAME  — e.g. nginx01.example.com
#
# Include the RSA section, the ECDSA section, or both (dual-stack).
# Comment out the section(s) you don't use.
#
# Credentials (from server/init/create-nginx-role.sh):
#   /etc/vault-agent/role_id    — static
#   /etc/vault-agent/secret_id  — sensitive, mode 0600

vault {
  address = "VAULT_ADDR"
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
      path = "/run/vault-agent/token"
      mode = "0600"
    }
  }
}

# ── ECDSA certificate ─────────────────────────────────────────────────────────
# Path: secret/certs/SERVER_HOSTNAME/ecdsa
# Files: /run/vault/ssl/ecdsa/{server.crt, server.key, ssl_password}

template {
  source      = "/etc/vault-agent/tpl/ecdsa/server.crt.tpl"
  destination = "/run/vault/ssl/ecdsa/server.crt"
  perms       = "0644"
  command     = "/etc/vault-agent/hooks/reload-nginx.sh"
}

template {
  source      = "/etc/vault-agent/tpl/ecdsa/server.key.tpl"
  destination = "/run/vault/ssl/ecdsa/server.key"
  perms       = "0640"
}

template {
  source      = "/etc/vault-agent/tpl/ecdsa/ssl_password.tpl"
  destination = "/run/vault/ssl/ecdsa/ssl_password"
  perms       = "0640"
}

# ── RSA certificate (include for dual-stack or RSA-only) ─────────────────────
# Path: secret/certs/SERVER_HOSTNAME/rsa
# Files: /run/vault/ssl/rsa/{server.crt, server.key, ssl_password}
#
# template {
#   source      = "/etc/vault-agent/tpl/rsa/server.crt.tpl"
#   destination = "/run/vault/ssl/rsa/server.crt"
#   perms       = "0644"
#   command     = "/etc/vault-agent/hooks/reload-nginx.sh"
# }
#
# template {
#   source      = "/etc/vault-agent/tpl/rsa/server.key.tpl"
#   destination = "/run/vault/ssl/rsa/server.key"
#   perms       = "0640"
# }
#
# template {
#   source      = "/etc/vault-agent/tpl/rsa/ssl_password.tpl"
#   destination = "/run/vault/ssl/rsa/ssl_password"
#   perms       = "0640"
# }
