# Policy: certmgr-push
# Assigned to CertMgr's AppRole (created in 01-kv-secrets).
# Allows writing (pushing) certificates to any server path.
# Path structure: secret/certs/<fqdn>/rsa  or  secret/certs/<fqdn>/ecdsa

path "secret/data/certs/*" {
  capabilities = ["create", "update", "read"]
}

path "secret/metadata/certs/*" {
  capabilities = ["read", "list", "delete"]
}
