# 02 — Internal Root CA (PKI)

## What this does

Enables Vault's PKI secrets engine and creates an internal root Certificate Authority (CA).
From this point Vault can issue TLS certificates on demand — no external CA needed.

**PKI secrets engine** is Vault's built-in certificate authority. It generates certificates
dynamically, tracks expiry, and can automatically revoke them. Certificates are short-lived
by design: instead of storing long-lived certs, you request a new one when needed.

**Root CA** is the trust anchor. Any client that trusts the root CA will automatically
trust all certificates issued by Vault. The root CA certificate is saved to
`02-pki-internal-ca/root-ca.crt` — distribute this to your trust stores.

**CRL / OCSP** (Certificate Revocation List / Online Certificate Status Protocol) are
mechanisms for clients to check whether a certificate has been revoked. The URLs for these
are embedded into every certificate Vault issues, so clients can look them up. These URLs
must point to the **public address** of your Vault server.

## What gets created

| Resource | Path | Purpose |
|----------|------|---------|
| PKI engine | `pki/` | Certificate authority |
| Root CA cert | `02-pki-internal-ca/root-ca.crt` | Trust anchor — distribute to clients |
| PKI URLs | `pki/config/urls` | CRL / OCSP / issuer URLs (public address) |
| CRL config | `pki/config/crl` | 24h expiry, auto-rebuild |
| Role | `pki/roles/server` | Controls what certificates can be issued |

## Prerequisites

- Vault running and unsealed
- `server/init/setup.sh` completed

## Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VAULT_ADDR` | yes | Local connection address. Default: `http://127.0.0.1:8100` |
| `VAULT_TOKEN` | yes | Root token. Auto-read from `server/init/vault-init.json` if present. |
| `VAULT_API_ADDR` | yes | **Public URL of this Vault server.** Written into every certificate as the CRL/OCSP URL. Clients validating certificates will fetch from this address. Must not be localhost. Example: `https://vault.example.com` |
| `VAULT_DOMAIN` | yes | **Domain for certificate issuance.** The `server` role will only issue certificates for hostnames under this domain. Example: `example.com` covers `host.example.com`, `app.example.com` |

> **Note:** `VAULT_ADDR` and `VAULT_API_ADDR` look similar but serve completely different
> purposes. `VAULT_ADDR` is how *you* connect to Vault right now. `VAULT_API_ADDR` is what
> gets written *inside* Vault and into every certificate — it must be the address *clients*
> use to reach Vault, not your admin connection.

## Run

```bash
bash 02-pki-internal-ca/setup.sh
```

Or with variables pre-set:

```bash
export VAULT_ADDR=http://127.0.0.1:8100
export VAULT_TOKEN=$(jq -r '.root_token' server/init/vault-init.json)
export VAULT_API_ADDR=https://vault.example.com
export VAULT_DOMAIN=example.com
bash 02-pki-internal-ca/setup.sh
```

## Verify

```bash
# PKI engine is listed
vault secrets list

# Issuer URLs are set to the public address
vault read pki/config/urls

# Root CA is readable
curl -s http://127.0.0.1:8100/v1/pki/ca/pem

# List roles
vault list pki/roles
```

## Test — issue a certificate

```bash
vault write pki/issue/server \
  common_name=test.example.com \
  ttl=24h
```

You should see a certificate, private key, and CA chain in the output.

## Distributing the Root CA

For clients to trust certificates issued by Vault, they must trust the root CA:

```bash
# The root CA was saved here
cat 02-pki-internal-ca/root-ca.crt

# Linux — add to system trust store
sudo cp 02-pki-internal-ca/root-ca.crt /usr/local/share/ca-certificates/vault-internal-ca.crt
sudo update-ca-certificates

# Or fetch directly from Vault
curl -s http://127.0.0.1:8100/v1/pki/ca/pem > vault-ca.crt
```
