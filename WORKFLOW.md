# Simple Workflow

## One Command to Start

```bash
./start-vault.sh
```

This does everything:
1. Starts Vault container (or resumes existing)
2. Initializes Vault (generates unseal key + root token)
3. Checks if configured
4. Guides next step

---

## Interactive Menu

When you run `./start-vault.sh`:

```
Vault Already Exists

Found existing Vault at: server/init/vault-init.json

Options:
  1. Continue with existing Vault (resume)
  2. Start fresh (delete all data, keep config)
  3. Start from scratch (delete ALL data)
  4. Exit

Choose (1-4):
```

Choose option based on your needs.

---

## After start-vault.sh Completes

### First Time Only

```bash
./setup-vault.sh
```

Interactive prompts:
- Vault domain
- HTTPS port
- Public API URL
- Certificate domain

Creates `.env` file with your settings.

---

### Deploy Provisioners

Either automated:
```bash
./setup-provisioners.sh
```

Or educational (with explanations):
```bash
./guided-tour.sh
```

---

## Summary

| Step | Command | When |
|------|---------|------|
| Start Vault | `./start-vault.sh` | Every session |
| Configure | `./setup-vault.sh` | First time only |
| Deploy | `./setup-provisioners.sh` | After configuring |

That's it!

---

## Script Modes

| Mode | File | Behavior |
|------|------|----------|
| **Automated** | `./setup-provisioners.sh` | Runs all 7 provisioners, no prompts |
| **Educational** | `./guided-tour.sh` | Explains each step, shows verification commands |
| **Manual** | Run individually | Each provisioner in `server/provisioners/XX-*/` |

---

## Examples

**Fresh start from scratch:**
```bash
./start-vault.sh           # Choose option 3
./setup-vault.sh          # Fill in your config
./setup-provisioners.sh    # Deploy everything
```

**Resume and re-provision:**
```bash
./start-vault.sh           # Choose option 1
./setup-provisioners.sh    # Provision again
```

**Learn how it works:**
```bash
./start-vault.sh
./setup-vault.sh
./guided-tour.sh           # Step-by-step with explanations
```

---

## Files Created by Each Step

| Step | Creates | Purpose |
|------|---------|---------|
| `./start-vault.sh` | `server/init/vault-init.json` | Unseal key + root token |
| `./setup-vault.sh` | `.env` | Your Vault configuration |
| Provisioners | `server/provisioners/*/credentials/` | Server credentials |
