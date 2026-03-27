# 02 — PKI Internal CA

Enables the PKI secrets engine and generates an internal root CA.
This is the foundation for both manual certificate issuance and ACME (step 03).

## What this sets up

- PKI secrets engine at `pki/`
- Internal root CA (EC P-256, 10-year validity)
- PKI issuer URLs pointing to the external Vault address
- Role `server` — for issuing server certificates

## Prerequisites

- Vault initialized and unsealed
- `VAULT_API_ADDR` set to the external Vault URL (e.g. `https://vault.example.com`)

## Run

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' ../server/init/vault-init.json)
export VAULT_API_ADDR=https://vault.example.com

bash 02-pki-internal-ca/setup.sh
```

The root CA certificate is saved to `02-pki-internal-ca/root-ca.crt`.
Import it into your browser or OS trust store to trust Vault-issued certs.

## Verify

```bash
# Check PKI engine
vault secrets list

# Check PKI configuration
vault read pki/config/urls
vault read pki/config/crl

# List roles
vault list pki/roles

# Read role details
vault read pki/roles/server
```

## Test — Issue a certificate manually

```bash
# Issue a test certificate
vault write pki/issue/server \
  common_name="test.example.com" \
  ttl=24h

# The response contains:
#   certificate       — leaf cert (PEM)
#   issuing_ca        — CA cert (PEM)
#   ca_chain          — full chain
#   private_key       — private key (PEM) — shown ONCE, not stored
#   serial_number     — for revocation
```

## Test — Sign a CSR

```bash
# Generate a CSR
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout test.key -out test.csr \
  -subj "/CN=test.example.com"

# Sign it
vault write pki/sign/server \
  csr=@test.csr \
  common_name="test.example.com" \
  ttl=24h

# Clean up
rm test.key test.csr
```

## Revoke a certificate

```bash
# Revoke by serial number
vault write pki/revoke serial_number="<serial>"

# Rotate CRL
vault write pki/crl/rotate

# Check CRL
curl -s https://vault.example.com/v1/pki/crl | openssl crl -inform DER -text -noout
```

## CA certificate

The root CA is at:
```
https://vault.example.com/v1/pki/ca      (DER format)
https://vault.example.com/v1/pki/ca/pem  (PEM format)
```

Download and trust it:
```bash
curl -s https://vault.example.com/v1/pki/ca/pem -o vault-ca.crt

# Linux — add to system trust store
sudo cp vault-ca.crt /usr/local/share/ca-certificates/vault-ca.crt
sudo update-ca-certificates
```
