# 03 — ACME Protocol

## What this does

Enables the ACME protocol on Vault's PKI engine. ACME (Automatic Certificate Management
Environment) is the same protocol used by Let's Encrypt. Once enabled, any ACME client
(certbot, acme.sh, Domino CertMgr, Caddy, Traefik, etc.) can request and renew certificates
from this Vault server automatically — using the same tooling they use with Let's Encrypt,
but against your private CA.

**Requires:** `02-pki-internal-ca` completed. ACME runs on top of the PKI engine.

**Requires:** Vault 1.14 or later.

## What gets created

| Resource | Path | Purpose |
|----------|------|---------|
| Cluster path | `pki/config/cluster` | Base URL for all ACME endpoints (must be public) |
| ACME config | `pki/config/acme` | Enables ACME, sets default policy |
| Role | `pki/roles/acme` | Controls domains ACME clients may request |

## ACME directory URL

Once configured, ACME clients point to:

```
https://your-vault/v1/pki/acme/directory
```

This is the entry point for all ACME operations (discovery, nonce, order, challenge, finalize).

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VAULT_ADDR` | yes | Local connection address. Default: `http://127.0.0.1:8100` |
| `VAULT_TOKEN` | yes | Root token. Auto-read from `server/init/vault-init.json` if present. |
| `VAULT_API_ADDR` | yes | **Public URL of this Vault server.** Written into `pki/config/cluster` as the base for all ACME endpoint URLs. ACME clients follow redirects to these URLs — must be externally reachable. Example: `https://vault.example.com` |
| `VAULT_DOMAIN` | yes | **Domain for ACME certificate requests.** Only hostnames under this domain may be requested via ACME. Example: `example.com` |

## Run

```bash
bash 03-pki-acme/setup.sh
```

Or with variables pre-set:

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)
export VAULT_API_ADDR=https://vault.example.com
export VAULT_DOMAIN=example.com
bash 03-pki-acme/setup.sh
```

## Verify

```bash
# ACME is enabled
vault read pki/config/acme

# Cluster path is set to the public address
vault read pki/config/cluster

# ACME directory is reachable
curl -s https://vault.example.com/v1/pki/acme/directory | jq .
```

The directory response lists all ACME endpoint URLs. All of them should use your public address.

## Test — issue a certificate with acme.sh

```bash
# Issue a certificate (server must be reachable for HTTP-01 challenge)
acme.sh --issue \
  --server https://vault.example.com/v1/pki/acme/directory \
  -d host.example.com \
  --standalone

# The issued certificate will be signed by your Vault internal CA.
# Clients must trust the root CA from 02-pki-internal-ca/root-ca.crt.
```

## Test — issue a certificate with certbot

```bash
certbot certonly \
  --server https://vault.example.com/v1/pki/acme/directory \
  --standalone \
  -d host.example.com
```

## Domino CertMgr integration

In CertMgr, set the ACME directory URL to:

```
https://vault.example.com/v1/pki/acme/directory
```

CertMgr will use the ACME protocol to request and automatically renew certificates.
The issued certificates are signed by your internal Vault CA. Ensure all Domino clients
and browsers trust the root CA from `02-pki-internal-ca/root-ca.crt`.

## Challenge types

Vault's ACME supports **HTTP-01** and **DNS-01** challenges.

- **HTTP-01**: The ACME client temporarily serves a token on `http://<domain>/.well-known/acme-challenge/`. Vault fetches it to verify domain ownership. The server must be reachable on port 80 from Vault.
- **DNS-01**: The client creates a DNS TXT record. Useful when port 80 is not available.
