# 01 — KV Secrets Engine

Enables the KV v2 secrets engine and creates the CertMgr AppRole used to
push TLS certificates into Vault.

## What this sets up

- KV v2 secrets engine at `secret/`
- Policy `certmgr-push` — allows writing to `secret/certs/*`
- AppRole auth method
- AppRole `certmgr` — used by CertMgr to push certificates

## Prerequisites

Vault initialized and unsealed (`server/init/setup.sh` completed).

## Run

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' ../server/init/vault-init.json)

bash 01-kv-secrets/setup.sh
```

Credentials are saved to `01-kv-secrets/certmgr-approle.env` (mode 600).

## Verify

```bash
# Check secrets engine is enabled
vault secrets list

# Check AppRole auth is enabled
vault auth list

# Check the certmgr role exists
vault read auth/approle/role/certmgr

# Check the policy
vault policy read certmgr-push
```

## Test

```bash
# Write a test secret
vault kv put secret/certs/test.example.com/ecdsa \
  chain="test-chain" \
  encrypted_key="test-key" \
  key_password="test-pass"

# Read it back
vault kv get secret/certs/test.example.com/ecdsa

# List
vault kv list secret/certs/

# Clean up
vault kv delete secret/certs/test.example.com/ecdsa
vault kv metadata delete secret/certs/test.example.com/ecdsa
```

## Test AppRole login

```bash
source 01-kv-secrets/certmgr-approle.env

TOKEN=$(vault write -field=token auth/approle/login \
  role_id="$VAULT_ROLE_ID" \
  secret_id="$VAULT_SECRET_ID")

# Verify the token has the right policy
VAULT_TOKEN="$TOKEN" vault token lookup

# Verify it can write a cert
VAULT_TOKEN="$TOKEN" vault kv put secret/certs/test.example.com/ecdsa \
  chain="test" encrypted_key="test" key_password="test"

# Clean up
vault kv metadata delete secret/certs/test.example.com/ecdsa
```

## Secret path structure

```
secret/certs/<server-fqdn>/ecdsa
secret/certs/<server-fqdn>/rsa
```

Fields per secret:

| Field | Description |
|-------|-------------|
| `chain` | Full PEM certificate chain (leaf + intermediates) |
| `encrypted_key` | AES-256 encrypted PEM private key |
| `key_password` | Decryption password for the key |
| `cn` | Certificate common name |
| `cert_type` | `rsa`, `ecdsa`, or `tls` |
| `serial` | Certificate serial number |
| `not_after` | Expiry timestamp |
| `pushed_at` | ISO-8601 push timestamp |
