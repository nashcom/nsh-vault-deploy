# Vault Provisioners

Step-by-step configuration scripts for HashiCorp Vault.

Run these **after** initializing Vault with `server/init/setup.sh`.
Each provisioner is independent and idempotent — safe to re-run.

## Prerequisites

```bash
# Vault must be running and unsealed
cd server && docker compose up -d
bash init/setup.sh
```

Two environment variables control the provisioners — they serve different purposes:

```bash
# VAULT_ADDR — how you connect to Vault. Always the local address.
# You configure Vault locally regardless of where it is publicly reachable.
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)

# VAULT_API_ADDR — the public URL written *into* Vault's configuration.
# Only needed for 02-pki-internal-ca and 03-pki-acme.
# Not used to connect — it gets stored inside Vault as:
#   - The CRL/OCSP/CA issuer URL embedded in every certificate PKI issues
#   - The base URL for ACME endpoints that clients redirect to
# Must be the address external clients can reach:
export VAULT_API_ADDR=https://vault.example.com
```

## Provisioners

| Directory | What it sets up | Needs `VAULT_API_ADDR` |
|-----------|----------------|----------------------|
| `01-kv-secrets/` | KV v2 secrets engine + CertMgr AppRole | no |
| `02-pki-internal-ca/` | Internal root CA + PKI secrets engine | yes — embedded in certificates |
| `03-pki-acme/` | ACME protocol on the PKI engine | yes — embedded in ACME config |
| `04-approle-nginx/` | Per-server AppRoles for NGINX cert delivery | no |

## Running order

Provisioners can be run independently or in sequence.
PKI provisioners depend on each other (run 02 before 03).

```bash
cd provisioners

bash 01-kv-secrets/setup.sh
bash 02-pki-internal-ca/setup.sh
bash 03-pki-acme/setup.sh
bash 04-approle-nginx/setup.sh
```

## Vault CLI quick reference

```bash
# Status
vault status

# List enabled secrets engines
vault secrets list

# List enabled auth methods
vault auth list

# List policies
vault policy list

# Read a policy
vault policy read <name>

# List KV secrets (after 01-kv-secrets)
vault kv list secret/certs/

# List PKI roles (after 02-pki-internal-ca)
vault list pki/roles
```
