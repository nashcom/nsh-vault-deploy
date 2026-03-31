# Getting Started with nsh-vault-deploy

## Quick Start

1. **Copy configuration template:**
   ```bash
   cp .env.example .env
   ```

2. **Edit .env** with your values:
   ```bash
   nano .env
   ```
   Key variables:
   - `VAULT_FQDN` - Your Vault server hostname
   - `VAULT_API_ADDR` - Public HTTPS URL for certificate issuance
   - `VAULT_DOMAIN` - Domain for PKI (e.g., example.com)
   - `VAULT_ADDR` - Internal connection (localhost for dev)

3. **Start Vault:**
   ```bash
   cd server
   docker compose up -d
   bash init/setup.sh
   ```

4. **Run provisioners in order:**
   ```bash
   cd server/provisioners
   bash 01-kv-secrets/setup.sh
   bash 02-pki-internal-ca/setup.sh
   bash 03-pki-intermediate-ca/setup.sh
   bash 04-pki-acme/setup.sh
   bash 05-approle-nginx/setup.sh <server-fqdn>     # per-server
   bash 06-mtls-bootstrap/setup.sh
   bash 07-pki-certmgr/setup.sh
   ```

## Directory Structure

```
nsh-vault-deploy/
├── .env                              ← Your configuration (gitignored)
├── .env.example                      ← Template: copy this
├── script_lib.sh                     ← Shared shell functions
├── vault.sh                          ← Vault CLI wrapper
│
├── server/
│   ├── docker-compose.yml            ← Vault container config
│   ├── config/vault.hcl              ← Vault server config
│   ├── init/setup.sh                 ← Initialize Vault
│   │
│   └── provisioners/                 ← Configuration scripts
│       ├── 01-kv-secrets/            ← KV secrets + AppRoles
│       ├── 02-pki-internal-ca/       ← Root CA
│       ├── 03-pki-intermediate-ca/   ← Intermediate CA
│       ├── 04-pki-acme/              ← ACME protocol
│       ├── 05-approle-nginx/         ← NGINX per-server AppRole
│       ├── 06-mtls-bootstrap/        ← mTLS cert auth
│       └── 07-pki-certmgr/           ← Domino CertMgr role
│
└── client/
    ├── nginx/                        ← NGINX integration
    └── ...
```

## Key Improvements

### Single Configuration File
- All variables in one `.env` at project root
- Loaded by all provisioners automatically
- Persisted across runs (no re-prompting)

### Logical Organization
- Each provisioner directory contains:
  - `setup.sh` - Configuration script
  - Policy files (HCL) - Co-located with provisioner
  - `README.md` - Step-specific documentation
- Easy to find what each provisioner does

### Reduced Path Complexity
- Consistent relative paths (still portable)
- Policy files moved from `server/policies/` to provisioner directories
- No more searching for scattered policy definitions

## Environment Variables

All provisioners use these variables (loaded from `.env`):

| Variable | Purpose | Example |
|----------|---------|---------|
| `VAULT_ADDR` | Internal connection | http://127.0.0.1:8100 |
| `VAULT_TOKEN` | Root token | (auto-loaded from vault-init.json) |
| `VAULT_API_ADDR` | External public URL | https://vault.example.com |
| `VAULT_FQDN` | Server hostname | vault.example.com |
| `VAULT_DOMAIN` | PKI domain | example.com |

## Provisioning Sequence

1. **01-kv-secrets** - Create KV v2 engine and CertMgr AppRole
2. **02-pki-internal-ca** - Generate root CA certificate
3. **03-pki-intermediate-ca** - Create intermediate CA (signed by root)
4. **04-pki-acme** - Enable ACME protocol on intermediate
5. **05-approle-nginx** - Per-server NGINX AppRole (run once per server)
6. **06-mtls-bootstrap** - Enable cert auth for mutual TLS
7. **07-pki-certmgr** - Create Domino CertMgr role and token

## Troubleshooting

### Variables not loading from .env
Ensure `.env` exists at project root and is readable:
```bash
ls -la .env
```

### "script_lib.sh not found"
Ensure you're running scripts from the correct directory:
```bash
cd server/provisioners/01-kv-secrets
bash setup.sh
```

### Policy files not found
Policy files are now co-located with provisioners. For example, `01-kv-secrets/certmgr-push.hcl` is in the provisioner directory, not in a central policies folder.

## Next Steps

- Deploy NGINX servers using `bash 05-approle-nginx/setup.sh <fqdn>`
- Enroll mTLS clients using `bash 06-mtls-bootstrap/enroll.sh <fqdn>`
- Issue ACME certificates via the ACME directory URL
- Deploy CertMgr with the token from step 07

See individual provisioner READMEs for detailed configuration options.
