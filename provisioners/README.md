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

## Environment variables

Three variables control the provisioners — each serves a different purpose:

| Variable | Purpose | When needed |
|----------|---------|-------------|
| `VAULT_ADDR` | **Connection address.** How your terminal connects to Vault. Always the local address — you configure Vault locally even if it is publicly reachable. | All provisioners |
| `VAULT_TOKEN` | **Authentication.** Root token from `server/init/setup.sh`. Auto-read from `server/init/vault-init.json` if present. | All provisioners |
| `VAULT_API_ADDR` | **Public URL written into Vault.** Gets stored inside Vault as the base URL for CRL/OCSP URLs (in certificates) and ACME endpoints. Must be the address external clients use to reach Vault — never localhost. | 02, 03 |
| `VAULT_DOMAIN` | **Certificate domain.** The domain for which Vault will issue certificates. `allow_subdomains=true` covers all hostnames under it. | 02, 03 |

```bash
# Always needed
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)

# Needed for PKI provisioners (02, 03)
export VAULT_API_ADDR=https://vault.example.com   # public URL — goes into Vault config
export VAULT_DOMAIN=example.com                   # domain — goes into PKI roles
```

If any variable is not exported, the script will prompt for it.

## Provisioners

| Directory | What it sets up | Needs `VAULT_API_ADDR` | Needs `VAULT_DOMAIN` |
|-----------|----------------|----------------------|---------------------|
| `01-kv-secrets/` | KV v2 secrets engine + CertMgr AppRole | no | no |
| `02-pki-internal-ca/` | Internal root CA + PKI secrets engine | yes — in certificate CRL/OCSP URLs | yes — PKI role allowed_domains |
| `03-pki-acme/` | ACME protocol on the PKI engine | yes — in ACME cluster path | yes — ACME role allowed_domains |
| `04-approle-nginx/` | Per-server AppRoles for NGINX cert delivery | no | no |

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
