# Quick Start Guide

Complete workflow to get Vault up and running with provisioning.

## Overview

Three stages:
1. **Start** — Initialize Vault container
2. **Configure** — Set parameters once
3. **Provision** — Deploy PKI and authentication

## Full Workflow

### Stage 1: Start Vault

```bash
./start-vault.sh
```

This interactive script handles:
- **Resume existing**: If Vault already exists, reconnect to it
- **Start fresh**: Delete vault data, keep configuration
- **Start from scratch**: Delete everything including .env
- **Start new**: Start Vault container for the first time

Output will guide you to the next step.

---

### Stage 2: Already Done!

`./start-vault.sh` automatically:
- Waits for Vault to be ready
- Initializes Vault (creates unseal key + root token)
- Unseals Vault
- Saves credentials to `server/init/vault-init.json`

**Keep `server/init/vault-init.json` safe!** It contains the unseal key and root token.

If you need to reinitialize:
```bash
cd server/init
./setup.sh
```

---

### Stage 3: Configure

Configure all Vault parameters once:

```bash
./setup-vault.sh
```

Interactive prompts for:
- `VAULT_FQDN` — Your domain (e.g., vault.company.com)
- `VAULT_HTTPS_PORT` — HTTPS port (443 for standard)
- `VAULT_API_ADDR` — Public HTTPS URL (auto-generated)
- `VAULT_ADDR` — Internal address for provisioning (usually localhost)
- `VAULT_DOMAIN` — Certificate domain (e.g., company.com)
- `VAULT_TOKEN` — Root token (optional, auto-loads from init file)

Creates `.env` with all values.

---

### Stage 4A: Automated Provisioning

Run all provisioners automatically (no prompts):

```bash
./setup-provisioners.sh
```

Runs all 7 steps:
1. KV secrets + AppRole
2. Root CA
3. Intermediate CA
4. ACME
5. Per-server AppRole (NGINX)
6. mTLS bootstrap
7. CertMgr role

Uses defaults for per-server provisioners (nginx01.example.com).

To provision for different servers:

```bash
export SERVER_HOSTNAME=nginx02.company.com
./setup-provisioners.sh
```

---

### Stage 4B: Guided Tour (Learning)

Interactive educational walkthrough:

```bash
./guided-tour.sh
```

For each step:
- Runs the provisioner
- Explains what happened
- Shows verification commands
- Pauses for you to absorb before next step

Perfect for understanding the architecture.

---

## Full Command Sequence

**First time (from scratch):**

```bash
./start-vault.sh
# Automatically: starts container + initializes Vault

./setup-vault.sh
# Sets up .env file

# Then provision (choose one):
./setup-provisioners.sh              # Automated
# OR
./guided-tour.sh                     # Educational
```

**Resuming existing Vault:**

```bash
./start-vault.sh
# Choose option 1 (Resume existing)

./setup-provisioners.sh       # Or ./guided-tour.sh
```

**Start fresh (keep config):**

```bash
./start-vault.sh
# Choose option 2 (Start fresh)
# Automatically: reinitializes Vault

./setup-provisioners.sh
```

**Start completely from scratch:**

```bash
./start-vault.sh
# Choose option 3 (From scratch)
# Automatically: deletes everything

./setup-vault.sh            # Configure again
./setup-provisioners.sh
```

---

## Environment Variables

All provisioners read from `.env` (created by `setup-vault.sh`):

| Variable | Example | Purpose |
|----------|---------|---------|
| `VAULT_FQDN` | vault.company.com | Server hostname |
| `VAULT_HTTPS_PORT` | 443 | Public HTTPS port |
| `VAULT_API_ADDR` | https://vault.company.com | Public API URL |
| `VAULT_ADDR` | http://127.0.0.1:8100 | Internal provisioning address |
| `VAULT_DOMAIN` | company.com | Certificate domain |
| `VAULT_TOKEN` | (auto-loaded) | Root token |
| `SERVER_HOSTNAME` | nginx01.company.com | Per-server hostname (override for 05) |

---

## Modes Explained

### INTERACTIVE=true (setup-vault.sh)
- Always prompt for input
- Even if variable is set, user can override
- Used for initial configuration

### INTERACTIVE=false (setup-provisioners.sh, guided-tour.sh)
- Only prompt if variable is empty
- Reads from .env if variable is set
- Silent/automated for demos and scripting

### GUIDED=true (guided-tour.sh)
- INTERACTIVE=false + pauses + explanations
- Shows what happened after each step
- Shows verification commands
- Educational walkthrough

---

## Troubleshooting

### "vault-init.json not found"
Vault hasn't been initialized yet. Run:
```bash
cd server && bash init/setup.sh
```

### ".env not found"
Configuration hasn't been set. Run:
```bash
./setup-vault.sh
```

### "Vault container won't start"
Check Docker:
```bash
cd server
docker compose logs vault
```

### "INTERACTIVE variable not recognized"
Update `script_lib.sh`. The variable should be set automatically by each script.

---

## Next Steps

After provisioning:

1. **Access Vault UI**
   - URL: `$VAULT_API_ADDR` (from .env)
   - Import root CA from `server/provisioners/02-pki-internal-ca/root-ca.crt` to browser for trusted access

2. **Deploy Clients**
   - Credentials: `server/provisioners/*/credentials/`
   - NGINX: `05-approle-nginx/credentials/`
   - mTLS: `06-mtls-bootstrap/credentials/`

3. **Request Certificates**
   - ACME: `${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory`
   - CertMgr: Use token from `07-pki-certmgr` with `domino-certmgr` role

4. **Rotate Tokens**
   ```bash
   bash server/provisioners/07-pki-certmgr/renew-token.sh
   ```

---

## Architecture

```
start-vault.sh          ← Start/stop container, manage volumes
     ↓
server/init/setup.sh    ← Initialize & unseal Vault
     ↓
setup-vault.sh         ← Configure parameters (.env)
     ↓
setup-provisioners.sh   ← Automated provisioning (01-07)
  OR
guided-tour.sh          ← Educational walkthrough (01-07)
```

Each step depends on the previous one completing successfully.

---

For detailed information, see:
- `GETTING_STARTED.md` — Architecture overview
- `server/provisioners/README.md` — Provisioner details
