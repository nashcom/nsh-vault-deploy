# Vault Server

Docker-based Vault server with two listeners:

| Listener | Port | Protocol | Purpose |
|----------|------|----------|---------|
| Internal | 8100 | HTTP | Admin operations, setup scripts, health checks |
| External | 8200 (→ 443) | HTTPS + TLS | Client access, ACME, API |

## Quick start

```bash
# 1. Bootstrap TLS certificate (first time only)
bash tls/bootstrap.sh vault.example.com

# 2. Copy and configure .env
cp .env.example .env
# Edit .env — set VAULT_FQDN, VAULT_API_ADDR, VAULT_DOMAIN

# 3. Start
docker compose up -d

# 4. Initialize and unseal
bash init/setup.sh
```

## .env settings

| Variable | Example | Description |
|----------|---------|-------------|
| `VAULT_FQDN` | `vault.example.com` | Public hostname — used in TLS cert and Vault api_addr |
| `VAULT_HTTPS_PORT` | `443` | Host port mapped to container port 8200 |
| `VAULT_API_ADDR` | `https://vault.example.com` | Full public URL — written into Vault as api_addr. Used in PKI CRL/OCSP URLs and ACME cluster path. Must not be localhost. |
| `VAULT_DOMAIN` | `example.com` | Domain for PKI certificate issuance |

## vault.sh — admin helper

`server/vault.sh` runs vault CLI commands against the local container.
It reads the root token from `init/vault-init.json` automatically.

```bash
# From the project root
./server/vault.sh status
./server/vault.sh secrets list
./server/vault.sh auth list
./server/vault.sh policy list
./server/vault.sh policy read certmgr-push
./server/vault.sh read pki/config/cluster
./server/vault.sh read pki/config/acme
./server/vault.sh read pki/config/urls
```

Override the token if needed:

```bash
export VAULT_TOKEN=<token>
./server/vault.sh status
```

## Diagnosing ACME nonce issues

If an ACME client reports "could not get nonce":

```bash
# 1. Verify ACME is enabled and the cluster path is correct
./server/vault.sh read pki/config/acme
./server/vault.sh read pki/config/cluster

# 2. Verify the directory returns the correct newNonce URL
curl -s https://vault.example.com/v1/pki/acme/directory | jq .newNonce

# 3. Test the nonce endpoint directly — must return Replay-Nonce header
curl -v -I https://vault.example.com/v1/pki/acme/new-nonce

# 4. Check for redirects — a 307 to the wrong address breaks nonce fetching
curl -v -I https://vault.example.com/v1/pki/acme/new-nonce 2>&1 | grep -E "^[<>]"
```

The nonce endpoint must return:
- HTTP `200` or `204`
- `Replay-Nonce: <value>` header

If the endpoint returns a `307 redirect`, the cluster path in `pki/config/cluster`
does not match the URL clients are using. Re-run provisioner `03-pki-acme` with the
correct `VAULT_API_ADDR`.

If `Replay-Nonce` is missing from a `200` response, a reverse proxy is stripping
non-standard headers. Configure the proxy to pass `Replay-Nonce` through.

## Directory layout

```
server/
├── config/
│   └── vault.hcl           Vault server configuration
├── init/
│   ├── setup.sh            Initialize, unseal, save credentials
│   └── vault-init.json     Init output — root token and unseal key (gitignored)
├── tls/
│   ├── bootstrap.sh        Generate self-signed TLS cert for first start
│   ├── vault.crt           TLS certificate (gitignored after bootstrap)
│   └── vault.key           TLS private key (gitignored after bootstrap)
├── policies/               HCL policy files
├── docker-compose.yml
├── .env.example            Template — copy to .env and configure
└── vault.sh                Admin helper — vault CLI via docker exec
```
