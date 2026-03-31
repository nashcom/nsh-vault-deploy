# Vault — Manual Operations Guide

Hands-on walkthrough of every operation we need, using the Vault CLI and raw
`curl` side by side.  Work through the sections in order the first time.

> **TL;DR —** Covers init, unseal, KV v2 secrets, policies, and AppRole
> authentication — each with both the Vault CLI command and the equivalent
> `curl` call. Work through sections 0–4 once to get a running Vault instance;
> return to individual sections as a reference. The Quick Reference table at
> the end summarises every command on one page.

---

## 0. Prerequisites

The Vault container must be running:

```bash
cd D:/claude/vault/server
docker compose up -d
docker compose ps        # should show "healthy" or "running"
```

Tell the CLI where Vault lives (internal HTTP port, no TLS needed for admin):

```bash
export VAULT_ADDR=http://127.0.0.1:8100
```

Check what Vault thinks its own status is:

```bash
vault status
# or with curl:
curl -s $VAULT_ADDR/v1/sys/health | jq
```

Fresh container output shows `initialized: false, sealed: true`.
After init it shows `initialized: true, sealed: false`.


## 1. Initialize Vault

Initialization happens exactly once (creates the master key shards and root token).
If the data volume was wiped, do it again.

```bash
vault operator init -key-shares=1 -key-threshold=1
```

```bash
# curl equivalent:
curl -s --request POST \
     --data '{"secret_shares":1,"secret_threshold":1}' \
     $VAULT_ADDR/v1/sys/init | jq
```

Save the output — you get:
- `Unseal Key 1: <base64>`  — needed every time the container restarts
- `Initial Root Token: hvs.<...>` — your master credential

Store them somewhere safe (for dev, a local file is fine):

```bash
# the setup.sh script saves them to init/vault-init.json automatically
# for manual work, just keep the terminal open or paste them into a file
```


## 2. Unseal Vault

After every restart Vault starts sealed (it won't serve requests until unsealed).

```bash
vault operator unseal <unseal-key>
```

```bash
# curl equivalent:
curl -s --request POST \
     --data "{\"key\":\"<unseal-key>\"}" \
     $VAULT_ADDR/v1/sys/unseal | jq
```

`sealed: false` in the response means you are good to go.


## 3. Authenticate (Root Token)

```bash
export VAULT_TOKEN=hvs.<your-root-token>
```

Every CLI command and every curl request uses this token.
For curl, pass it as a header:

```bash
# header used in all curl examples below:
# -H "X-Vault-Token: $VAULT_TOKEN"
```

Command to get the root token and store it in `VAULT_TOKEN`

```bash
export VAULT_TOKEN=$(cat vault-init.json | jq -r .root_token)
```

Verify it works:

```bash
vault token lookup
# or:
curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/auth/token/lookup-self | jq
```


## 4. Enable the KV v2 Secrets Engine

KV v2 stores versioned key-value secrets.
Enable it once at the path `secret/`:

```bash
vault secrets enable -path=secret kv-v2
```

```bash
# curl equivalent:
curl -s --request POST -H "X-Vault-Token: $VAULT_TOKEN" --data '{"type":"kv-v2"}' $VAULT_ADDR/v1/sys/mounts/secret | jq
```

List all mounted engines:

```bash
vault secrets list
# or:
curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/sys/mounts | jq 'keys'
```


## 5. Write a Secret

KV v2 API path pattern:  `secret/data/<your/path>`

```bash
vault kv put secret/certs/myserver.example.com/tls \
    chain="-----BEGIN CERTIFICATE-----\n..." \
    key="-----BEGIN PRIVATE KEY-----\n..." \
    cn="myserver.example.com" \
    not_after="Mar 26 00:00:00 2026 GMT"
```

```bash
# curl equivalent — use jq to build JSON so PEM newlines are escaped correctly:
FQDN="myserver.example.com"
CERT_FILE="/path/to/chain.pem"
KEY_FILE="/path/to/key.pem"

curl -s --request POST \
     -H "X-Vault-Token: $VAULT_TOKEN" \
     -H "Content-Type: application/json" \
     --data "$(jq -n \
         --rawfile chain  "$CERT_FILE" \
         --rawfile key    "$KEY_FILE" \
         --arg     cn     "$FQDN" \
         --arg     not_after "Mar 26 00:00:00 2026 GMT" \
         '{"data": {"chain": $chain, "key": $key, "cn": $cn, "not_after": $not_after}}')" \
     "$VAULT_ADDR/v1/secret/data/certs/$FQDN/tls" | jq
```

`--rawfile` reads the file into a jq variable and escapes newlines automatically.
Single-quoted `--data '...'` cannot expand shell variables or command output —
always use `--data "$(jq -n ...)"` when the payload contains dynamic values.

A successful write returns:

```json
{
  "data": {
    "created_time": "2026-03-26T12:00:00Z",
    "version": 1
  }
}
```


## 6. Read a Secret

```bash
vault kv get secret/certs/myserver.example.com/tls
```

```bash
# curl — reads latest version:
curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/data/certs/myserver.example.com/tls | jq
```

The response wraps the actual fields under `.data.data`:

```json
{
  "data": {
    "data": {
      "chain": "-----BEGIN CERTIFICATE-----\n...",
      "key":   "-----BEGIN PRIVATE KEY-----\n...",
      "cn":    "myserver.example.com"
    },
    "metadata": {
      "version": 1,
      "created_time": "2026-03-26T12:00:00Z"
    }
  }
}
```

Read a specific version:

```bash
vault kv get -version=1 secret/certs/myserver.example.com/tls
# or:
curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/certs/myserver.example.com/tls?version=1" | jq
```


## 7. List Secrets

List what paths exist under a prefix:

```bash
vault kv list secret/certs/
vault kv list secret/certs/myserver.example.com/
```

```bash
# curl — uses LIST method:
curl -s --request LIST -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/secret/metadata/certs/ | jq '.data.keys'
```


## 8. Delete a Secret

Soft-delete (marks version deleted, data recoverable):

```bash
vault kv delete secret/certs/myserver.example.com/tls
```

Permanent destroy (irrecoverable):

```bash
vault kv destroy -versions=1 secret/certs/myserver.example.com/tls
```

Delete all versions and metadata entirely:

```bash
vault kv metadata delete secret/certs/myserver.example.com/tls
```


## 9. Policies

A policy controls what paths a token or AppRole can access.

Write a simple read-only policy:

```bash
vault policy write nginx-read - <<'EOF'
path "secret/data/certs/myserver.example.com/*" {
  capabilities = ["read"]
}
EOF
```

```bash
# curl equivalent:
curl -s --request POST \
     -H "X-Vault-Token: $VAULT_TOKEN" \
     --data '{
       "policy": "path \"secret/data/certs/myserver.example.com/*\" { capabilities = [\"read\"] }"
     }' \
     $VAULT_ADDR/v1/sys/policies/acl/nginx-read | jq
```

List policies:

```bash
vault policy list
```

Read a policy:

```bash
vault policy read nginx-read
```


## 10. AppRole Authentication

AppRole is what the C++ program (CertMgr) uses — no long-lived token, just
`role_id` + `secret_id` which exchange for a short-lived token.

### Enable AppRole auth:

```bash
vault auth enable approle
```

### Create a role:

```bash
vault write auth/approle/role/certmgr-push \
    token_policies="certmgr-push" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=0       # 0 = never expires
```

### Get the role_id:

```bash
vault read auth/approle/role/certmgr-push/role-id
```

### Generate a secret_id:

```bash
vault write -f auth/approle/role/certmgr-push/secret-id
```

### Login (exchange role_id + secret_id for a token):

```bash
vault write auth/approle/login \
    role_id=<role-id> \
    secret_id=<secret-id>
```

```bash
# curl — this is exactly what the C++ program does:
curl -s --request POST \
     -H "Content-Type: application/json" \
     --data "{\"role_id\":\"<role-id>\",\"secret_id\":\"<secret-id>\"}" \
     $VAULT_ADDR/v1/auth/approle/login | jq
```

The response contains `auth.client_token` — use that as `X-Vault-Token`
for subsequent requests.  It expires after `token_ttl`.


## Quick Reference

| Operation | CLI | Curl path |
|---|---|---|
| Status | `vault status` | `GET /v1/sys/health` |
| Unseal | `vault operator unseal` | `POST /v1/sys/unseal` |
| Write secret | `vault kv put` | `POST /v1/secret/data/<path>` |
| Read secret | `vault kv get` | `GET /v1/secret/data/<path>` |
| List secrets | `vault kv list` | `LIST /v1/secret/metadata/<path>` |
| Delete secret | `vault kv delete` | `DELETE /v1/secret/data/<path>` |
| AppRole login | `vault write auth/approle/login` | `POST /v1/auth/approle/login` |

All curl requests require `-H "X-Vault-Token: $VAULT_TOKEN"` except the
unseal and login endpoints.


## What the C++ Program Does (preview)

The `vault_example` binary does exactly steps 10-login + section 5 in code:

1. Read `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID` from environment
2. POST to `/v1/auth/approle/login` → receive short-lived token
3. POST to `/v1/secret/data/certs/<fqdn>/tls` with cert payload
4. Zero all credential buffers from memory

Once you have Vault running and have manually pushed a secret with curl,
the C++ path will make complete sense.
