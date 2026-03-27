# 04 — AppRole for NGINX

Creates per-server AppRoles so NGINX servers can authenticate to Vault
and read their own TLS certificates from the KV secrets engine.

Requires: `01-kv-secrets` (AppRole auth method and KV engine must be enabled).

## What this sets up

- Policy `nginx-<hostname>` — read-only access to `secret/certs/<hostname>/*`
- AppRole `nginx-<hostname>` per server
- Credentials saved to `credentials/<hostname>/`

## Prerequisites

- `01-kv-secrets` completed (AppRole auth enabled, KV v2 at `secret/`)
- Vault initialized and unsealed

## Run — provision a new server

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' ../server/init/vault-init.json)

bash 04-approle-nginx/setup.sh nginx01.example.com
```

Credentials are saved to `04-approle-nginx/credentials/nginx01.example.com/`.
Copy them to the NGINX server (see `client/nginx/install.sh`).

## Verify

```bash
HOSTNAME=nginx01.example.com

# Check role
vault read auth/approle/role/nginx-${HOSTNAME}

# Check policy
vault policy read nginx-${HOSTNAME}
```

## Test AppRole login

```bash
HOSTNAME=nginx01.example.com
CREDS_DIR="04-approle-nginx/credentials/${HOSTNAME}"

TOKEN=$(vault write -field=token auth/approle/login \
  role_id="$(cat ${CREDS_DIR}/role_id)" \
  secret_id="$(cat ${CREDS_DIR}/secret_id)")

# Verify access — should be able to read own certs
VAULT_TOKEN="$TOKEN" vault kv get secret/certs/${HOSTNAME}/ecdsa

# Verify isolation — must NOT be able to read another server's certs
VAULT_TOKEN="$TOKEN" vault kv get secret/certs/other.example.com/ecdsa
# Expected: permission denied
```

## Push a sample certificate (for testing)

```bash
HOSTNAME=nginx01.example.com

vault kv put secret/certs/${HOSTNAME}/ecdsa \
  chain="$(openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -days 30 -nodes -subj "/CN=${HOSTNAME}" 2>/dev/null | \
    openssl x509 2>/dev/null)" \
  encrypted_key="placeholder-key" \
  key_password="placeholder-pass" \
  cert_type="ecdsa" \
  cn="${HOSTNAME}"
```

## Rotate credentials

```bash
HOSTNAME=nginx01.example.com

# Generate a new secret_id (old one is not automatically revoked)
NEW_SECRET=$(vault write -force -field=secret_id \
  auth/approle/role/nginx-${HOSTNAME}/secret-id)

printf '%s' "$NEW_SECRET" > "04-approle-nginx/credentials/${HOSTNAME}/secret_id"
chmod 600 "04-approle-nginx/credentials/${HOSTNAME}/secret_id"
```
