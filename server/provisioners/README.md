# Vault Provisioners

This directory contains numbered provisioning scripts that configure Vault for certificate issuance and authentication.

## Overview

Each provisioner is a numbered step that builds on the previous one:

| # | Directory | Purpose | Duration |
|---|-----------|---------|----------|
| 1 | `01-kv-secrets` | Create KV v2 secrets engine and CertMgr AppRole | ~10s |
| 2 | `02-pki-internal-ca` | Generate root CA certificate | ~10s |
| 3 | `03-pki-intermediate-ca` | Create intermediate CA signed by root | ~10s |
| 4 | `04-pki-acme` | Enable ACME protocol with role enforcement | ~5s |
| 5 | `05-approle-nginx` | Create per-server AppRole for NGINX | ~10s per server |
| 6 | `06-mtls-bootstrap` | Enable cert auth and issue client certs | ~10s per server |
| 7 | `07-pki-certmgr` | Create Domino CertMgr role and token | ~5s |

## Running the Provisioners

### Prerequisites

1. Vault must be initialized and unsealed:
   ```bash
   cd ../init
   bash setup.sh
   ```

2. Environment configuration (`.env` at project root):
   ```bash
   cp ../../.env.example ../../.env
   nano ../../.env
   ```

### Running in Sequence

```bash
cd server/provisioners

# Steps 1-4: Core PKI infrastructure (run once)
bash 01-kv-secrets/setup.sh
bash 02-pki-internal-ca/setup.sh
bash 03-pki-intermediate-ca/setup.sh
bash 04-pki-acme/setup.sh

# Steps 5-7: Per-server and service configuration
bash 05-approle-nginx/setup.sh nginx01.example.com
bash 05-approle-nginx/setup.sh nginx02.example.com
bash 06-mtls-bootstrap/setup.sh
bash 06-mtls-bootstrap/enroll.sh server01.example.com
bash 07-pki-certmgr/setup.sh
```

## Configuration

All provisioners load variables from `/.env` (at project root):

```bash
VAULT_ADDR=http://127.0.0.1:8100
VAULT_TOKEN=                          # auto-loaded from vault-init.json
VAULT_API_ADDR=https://vault.example.com
VAULT_DOMAIN=example.com
```

**Important:** Set these once in `.env` — all provisioners share the same configuration.

Variables are **persisted** across provisioner runs, so you won't be re-prompted.

## Policy Files

Policy HCL files are **co-located** with their provisioners:

| File | Location | Purpose |
|------|----------|---------|
| `certmgr-push.hcl` | `01-kv-secrets/` | AppRole policy for pushing certs |
| `nginx-read.hcl.tpl` | `05-approle-nginx/` | Per-server template for cert reading |
| `domino-certmgr.hcl` | `07-pki-certmgr/` | Policy for Domino CertMgr token |

This co-location makes it clear which policies belong to which provisioner.

## Architecture

### CA Hierarchy

```
PKI Root (pki/mount)
    └── Intermediate CA (pki-intermediate/mount)
        ├── ACME role (enforced domain restrictions)
        └── CertMgr role (Domino certificate issuance)
```

The root CA issues intermediates only; all end-entity certificates come from the intermediate.

### Authentication Methods

- **AppRole** (01, 05) - For automated deployments (cert delivery, CertMgr)
- **Cert Auth** (06) - For mutual TLS between services

## Typical Workflow

1. Run steps 1-4 once during initial setup
2. For each NGINX server:
   ```bash
   bash 05-approle-nginx/setup.sh nginx-hostname
   bash 06-mtls-bootstrap/enroll.sh nginx-hostname
   ```
3. Distribute credentials to the respective servers
4. Servers authenticate to Vault using their credentials

## Troubleshooting

### "policy file not found"
Policy files are in the provisioner directory, e.g., `01-kv-secrets/certmgr-push.hcl`. Check that the file exists alongside `setup.sh`.

### "role/acme is not a valid ACME role"
Ensure 03-pki-intermediate-ca runs before 04-pki-acme. The ACME role is created on the intermediate CA.

### "environment variable not loaded"
Ensure `.env` exists at project root and contains `VAULT_ADDR`, `VAULT_DOMAIN`, etc.

## Advanced Usage

### Viewing Vault Configuration

After running a provisioner, verify the configuration:

```bash
# After 02-pki-internal-ca
vault read pki/config/urls
vault list pki/roles

# After 04-pki-acme
vault read pki-intermediate/config/acme
vault read pki-intermediate/roles/acme

# After 07-pki-certmgr
vault policy read domino-certmgr
vault read pki-intermediate/roles/domino-certmgr
```

### Issuing Certificates

**Via ACME:**
```bash
acme.sh --issue --server https://vault.example.com/v1/pki-intermediate/acme/directory \
  -d test.example.com --standalone
```

**Via CertMgr token:**
```bash
vault write pki-intermediate/issue/domino-certmgr \
  common_name=app.example.com ttl=72h
```

## See Also

- `GETTING_STARTED.md` - Overall project quickstart
- Individual provisioner README files for step-specific details
- `server/config/vault.hcl` - Vault server configuration
