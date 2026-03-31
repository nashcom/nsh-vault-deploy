# Policy template: srvguard policy for a specific server
# Instantiated by enroll.sh <hostname>
# Each server reads only its own path — covers both rsa and ecdsa if present

# Replace SERVER_HOSTNAME with the actual FQDN, e.g. server01.example.com
# A wildcard cert pushed under its FQDN (e.g. star.example.com) is handled
# identically — no special case needed.

path "secret/data/certs/SERVER_HOSTNAME/*" {
  capabilities = ["read"]
}

path "secret/metadata/certs/SERVER_HOSTNAME/*" {
  capabilities = ["read"]
}
