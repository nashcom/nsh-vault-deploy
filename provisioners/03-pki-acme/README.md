# 03 — PKI ACME

Enables the ACME protocol on the PKI secrets engine so that standard ACME
clients (certbot, acme.sh, Caddy, etc.) can obtain certificates from Vault.

Requires: `02-pki-internal-ca` (PKI engine must be enabled first).
Requires: Vault 1.14.0+ (Community Edition or Enterprise).

## What this sets up

- ACME enabled on the `pki/` secrets engine
- Cluster path configured with the external Vault URL
- Role `acme` — the policy used for ACME-issued certificates
- ACME directory at `https://vault.example.com/v1/pki/acme/directory`

## Prerequisites

- `02-pki-internal-ca` completed
- `VAULT_API_ADDR` set to the public Vault URL
- Vault must be reachable externally on that URL (ACME clients reach it directly)

## Run

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' ../server/init/vault-init.json)
export VAULT_API_ADDR=https://vault.example.com

bash 03-pki-acme/setup.sh
```

## Verify

```bash
# ACME config
vault read pki/config/acme
vault read pki/config/cluster

# Roles available for ACME
vault list pki/roles
vault read pki/roles/acme
```

## Test — ACME directory

The ACME directory endpoint must return JSON:

```bash
curl -s https://vault.example.com/v1/pki/acme/directory | jq .
```

Expected response:
```json
{
  "newAccount": "https://vault.example.com/v1/pki/acme/new-account",
  "newNonce": "https://vault.example.com/v1/pki/acme/new-nonce",
  "newOrder": "https://vault.example.com/v1/pki/acme/new-order",
  "revokeCert": "https://vault.example.com/v1/pki/acme/revoke-cert",
  "keyChange": "https://vault.example.com/v1/pki/acme/key-change"
}
```

## Test — Issue certificate with acme.sh

```bash
# Install acme.sh if needed
# curl https://get.acme.sh | sh

# Register and issue (HTTP-01 challenge — port 80 must be reachable)
acme.sh --register-account \
  --server https://vault.example.com/v1/pki/acme/directory \
  -m admin@example.com

acme.sh --issue \
  --server https://vault.example.com/v1/pki/acme/directory \
  -d test.example.com \
  --standalone

# The certificate is at:
#   ~/.acme.sh/test.example.com/test.example.com.cer
#   ~/.acme.sh/test.example.com/test.example.com.key
```

## Test — Issue certificate with certbot

```bash
# HTTP-01 challenge (port 80 must be available on the ACME client host)
certbot certonly \
  --server https://vault.example.com/v1/pki/acme/directory \
  --standalone \
  -d test.example.com \
  --agree-tos \
  -m admin@example.com

# DNS-01 challenge (no port 80 requirement, needs DNS API access)
certbot certonly \
  --server https://vault.example.com/v1/pki/acme/directory \
  --manual \
  --preferred-challenges dns \
  -d test.example.com
```

## How ACME challenges work

Vault acts as the ACME CA. The ACME client handles the challenge:

- **HTTP-01**: Client serves a token at `http://<domain>/.well-known/acme-challenge/<token>`.
  Vault's ACME implementation will try to reach this URL to verify ownership.
  Requires port 80 to be accessible from Vault's perspective.

- **DNS-01**: Client adds a `_acme-challenge.<domain>` TXT record to DNS.
  Vault queries DNS to verify. No port requirements. Works behind NAT.

## ACME and the Vault CA trust

ACME clients need to trust Vault's root CA for TLS verification.
The Vault root CA is at `https://vault.example.com/v1/pki/ca/pem`.

If Vault's TLS cert is from a public CA (Let's Encrypt, ZeroSSL), ACME clients
can connect to Vault without extra CA configuration.
The *issued* certificates use the Vault internal CA — import `root-ca.crt`
(from step 02) to trust those.
