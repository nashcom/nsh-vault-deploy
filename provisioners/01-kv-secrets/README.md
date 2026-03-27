# 01 — KV Secrets + CertMgr AppRole

## What this does

Sets up the KV v2 secrets engine and an AppRole identity for Domino CertMgr to push
certificates into Vault.

**KV v2** (key/value version 2) is Vault's general-purpose secret store. This provisioner
mounts it at `secret/` and reserves the path `secret/certs/<hostname>/` for certificate
storage. Each Domino server stores its certificate and key there; NGINX servers read from
the same path.

**AppRole** is a Vault authentication method designed for machines and services (not humans).
A service authenticates with a Role ID (like a username) and a Secret ID (like a password)
to receive a short-lived Vault token. This provisioner creates the `certmgr` AppRole so
Domino CertMgr can authenticate to push certificates.

## What gets created

| Resource | Path | Purpose |
|----------|------|---------|
| KV v2 engine | `secret/` | Certificate and secret storage |
| Policy | `certmgr-push` | Allows write to `secret/data/certs/*` |
| AppRole | `auth/approle/role/certmgr` | Identity for Domino CertMgr |
| Credentials file | `01-kv-secrets/certmgr-approle.env` | Role ID + Secret ID for CertMgr |

## Prerequisites

- Vault running and unsealed
- `server/init/setup.sh` completed (provides `vault-init.json`)

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VAULT_ADDR` | yes | Local connection address. Default: `http://127.0.0.1:8100` |
| `VAULT_TOKEN` | yes | Root token. Auto-read from `server/init/vault-init.json` if present. |

These control **how you connect** to Vault. They never need to be the public address.

## Run

```bash
bash 01-kv-secrets/setup.sh
```

If variables are not set the script will prompt for them.
To skip prompts, export them first:

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)
bash 01-kv-secrets/setup.sh
```

## Verify

```bash
# KV engine is listed
vault secrets list

# Policy exists and has correct paths
vault policy read certmgr-push

# AppRole exists with correct settings
vault read auth/approle/role/certmgr
```

## Test

```bash
# Write a test secret
vault kv put secret/certs/test.example.com cert="FAKECERT" key="FAKEKEY"

# Read it back
vault kv get secret/certs/test.example.com

# Clean up
vault kv delete secret/certs/test.example.com
```

## Output

`certmgr-approle.env` contains the credentials CertMgr needs:

```
VAULT_ADDR=http://127.0.0.1:8100
VAULT_ROLE_ID=<role-id>
VAULT_SECRET_ID=<secret-id>
```

Copy these values into your Domino CertMgr configuration.
