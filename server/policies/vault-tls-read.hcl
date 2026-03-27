# Policy: vault-tls-read
# Assigned to the Vault Agent AppRole running on the Vault host.
# Read-only access to Vault's own TLS certificate.
# Secret path is consistent with the per-server model: secret/certs/<fqdn>/tls

path "secret/data/certs/+/tls" {
  capabilities = ["read"]
}

path "secret/metadata/certs/+/tls" {
  capabilities = ["read"]
}

# Allow the agent to call vault operator reload via the API
path "sys/replication/reindex" {
  capabilities = ["update"]
}
