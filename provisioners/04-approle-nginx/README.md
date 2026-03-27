# 04 — Per-Server AppRole for NGINX

## What this does

Creates an AppRole identity for each NGINX (or any web server) that needs to read
certificates from Vault. Each server gets:

- Its own **policy** — read-only access to its own certificate path only
- Its own **AppRole** — unique credentials, isolated from other servers
- A **credentials directory** with `role_id` and `secret_id` files to copy to the server

This follows the principle of least privilege: each server can only see its own
certificates, not those of any other server.

**Requires:** `01-kv-secrets` completed (KV engine and AppRole auth must exist).

## What gets created

| Resource | Path | Purpose |
|----------|------|---------|
| Policy | `nginx-<fqdn>` | Read-only on `secret/data/certs/<fqdn>/*` |
| AppRole | `auth/approle/role/nginx-<fqdn>` | Identity for the NGINX server |
| Credentials | `04-approle-nginx/credentials/<fqdn>/` | `role_id` + `secret_id` files |

Run this once per NGINX server you want to configure.

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VAULT_ADDR` | yes | Local connection address. Default: `http://127.0.0.1:8100` |
| `VAULT_TOKEN` | yes | Root token. Auto-read from `server/init/vault-init.json` if present. |
| Server FQDN | yes | Fully qualified hostname of the NGINX server. Pass as argument or enter when prompted. |

## Run

```bash
# Pass FQDN as argument
bash 04-approle-nginx/setup.sh nginx01.example.com

# Or run interactively (will prompt for FQDN)
bash 04-approle-nginx/setup.sh
```

## Verify

```bash
# Policy exists and covers the right path
vault policy read nginx-nginx01.example.com

# AppRole exists
vault read auth/approle/role/nginx-nginx01.example.com
```

## Deploy credentials to the NGINX server

```bash
# Copy role_id and secret_id to the server
scp 04-approle-nginx/credentials/nginx01.example.com/{role_id,secret_id} \
  root@nginx01.example.com:/etc/vault-agent/
```

These files are used by Vault Agent on the NGINX server to authenticate and retrieve
certificates. See `client/nginx/` for the Vault Agent configuration.

## Test authentication

From the NGINX server (or locally to test):

```bash
# Authenticate using the AppRole credentials
VAULT_TOKEN=$(vault write -field=token auth/approle/login \
  role_id=$(cat /etc/vault-agent/role_id) \
  secret_id=$(cat /etc/vault-agent/secret_id))

# Read a certificate (must have been pushed by CertMgr first)
VAULT_TOKEN=$VAULT_TOKEN vault kv get secret/certs/nginx01.example.com/current
```
