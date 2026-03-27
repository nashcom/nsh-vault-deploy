# vault — Private Key Distribution via HashiCorp Vault

Distributes TLS private keys and sensitive credentials to servers without
storing secrets in plaintext on disk. Part of the CertMgr ecosystem.

## Architecture

```
CertMgr
  │  generates cert + key, encrypts key, pushes compound secret
  ▼
HashiCorp Vault  (KV v2)
  │
  │  secret/certs/<fqdn>/ecdsa   ← chain, encrypted_key, key_password
  │  secret/certs/<fqdn>/rsa     ← same structure, RSA key
  │
  ├── Vault Agent (NGINX server)
  │     AppRole auth → render templates → tmpfs → ssl_password_file
  │     nginx -s reload fires automatically when secret version changes
  │
  └── Vault Agent / C helper (Domino server)
        AppRole auth → fetch password → C-API callback → unlock server.id
        Password never written to disk
```

## Secret Path Structure

```
secret/certs/<server-fqdn>/ecdsa    ← ECDSA cert + key for this server
secret/certs/<server-fqdn>/rsa      ← RSA cert + key (optional, dual-stack)
secret/domino/<server-fqdn>/password ← Domino server.id unlock password
```

**One secret per server.** The path is always the server's own FQDN — never
the certificate's CN or SAN. Each server looks up only its own name.

CertMgr decides which certificate to provision for each server and pushes it
to that server's path. If a wildcard certificate covers three servers, CertMgr
pushes it three times — once per server — each under the server's own FQDN:

```
secret/certs/nginx01.example.com/ecdsa   ← wildcard cert, nginx01's copy
secret/certs/nginx02.example.com/ecdsa   ← same wildcard cert, nginx02's copy
secret/certs/nginx03.example.com/ecdsa   ← dedicated cert, nginx03
```

Vault does not know or care about cert CNs or wildcards. Vault Agent on each
server fetches exactly one path — its own — and never sees another server's key.

No previous/rollback path — Vault KV v2 keeps full version history internally
if rollback is ever needed (`vault kv get -version=N`).

## Secret Fields (per cert entry)

| Field           | Content                                 |
|-----------------|-----------------------------------------|
| `chain`         | Full PEM chain (leaf + intermediates)   |
| `encrypted_key` | AES-256 encrypted PEM private key       |
| `key_password`  | Decryption password for the key         |
| `cn`            | Certificate CN                          |
| `cert_type`     | `rsa` or `ecdsa`                        |
| `serial`        | Certificate serial number               |
| `not_after`     | Expiry timestamp                        |
| `pushed_at`     | ISO-8601 push timestamp                 |

## Directory Structure

```
vault/
  server/                      — Vault server (shared infrastructure)
    docker-compose.yml
    config/vault.hcl
    policies/
      certmgr-push.hcl         — CertMgr write policy
      nginx-read.hcl.tpl       — Per-server read policy template
    init/
      setup.sh                 — One-time initialization
      create-nginx-role.sh     — Provision a new server
      push-sample-cert.sh      — Push test cert for pipeline testing

  client/
    nginx/                     — Deploy to each NGINX server
      install.sh               — Full client-side setup (run as root)
      vault-agent.hcl.tpl      — Vault Agent config template
      vault-agent.service      — systemd unit (mounts tmpfs)
      templates/
        ecdsa/                 — Templates for ECDSA cert
        rsa/                   — Templates for RSA cert
      hooks/reload-nginx.sh    — Validates + reloads NGINX after render
      nginx-ssl.conf.example

    domino/README.md           — Domino server.id design (planned)
```

## Quick Start

### 1. Start Vault

```bash
cd server
docker compose up -d
bash init/setup.sh
```

### 2. Provision an NGINX Server

```bash
# Creates AppRole scoped to this server's own secret path
bash server/init/create-nginx-role.sh nginx01.example.com

# Push a test cert to this server's path (wildcard or dedicated — CertMgr's choice)
bash server/init/push-sample-cert.sh nginx01.example.com ecdsa
```

### 3. Install Vault Agent on the NGINX Server

```bash
# ECDSA only (default)
sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200

# Both ECDSA and RSA (dual-stack)
sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200 both
```

### 4. NGINX Config

```nginx
# Single cert (ECDSA)
ssl_certificate     /run/vault/ssl/ecdsa/server.crt;
ssl_certificate_key /run/vault/ssl/ecdsa/server.key;
ssl_password_file   /run/vault/ssl/ecdsa/ssl_password;

# Dual-stack (add both, NGINX selects based on client capability)
ssl_certificate     /run/vault/ssl/ecdsa/server.crt;
ssl_certificate_key /run/vault/ssl/ecdsa/server.key;
ssl_certificate     /run/vault/ssl/rsa/server.crt;
ssl_certificate_key /run/vault/ssl/rsa/server.key;
ssl_password_file   /run/vault/ssl/ecdsa/ssl_password;
ssl_password_file   /run/vault/ssl/rsa/ssl_password;
```

## CertMgr Push (what CertMgr does on each renewal)

CertMgr pushes to each server's own path regardless of cert type.
For a wildcard cert covering multiple servers, it pushes once per server:

```bash
# Dedicated cert for nginx01
vault kv put secret/certs/nginx01.example.com/ecdsa \
    chain="$(cat nginx01.crt)"          \
    encrypted_key="$(cat nginx01.key)"  \
    key_password="$KEY_PASS"            \
    cert_type="ecdsa"                   \
    serial="..." not_after="..." pushed_at="..."

# Wildcard cert — pushed to each server individually under its own FQDN
for SERVER in nginx02.example.com nginx03.example.com; do
    vault kv put "secret/certs/${SERVER}/ecdsa" \
        chain="$(cat wildcard.crt)"         \
        encrypted_key="$(cat wildcard.key)" \
        key_password="$KEY_PASS"            \
        cert_type="ecdsa"                   \
        serial="..." not_after="..." pushed_at="..."
done
```

Vault Agent on each server detects the new secret version independently
and reloads NGINX. No manual intervention required.

## Security Properties

| Property | Mechanism |
|----------|-----------|
| Key encrypted at rest | AES-256 encrypted PEM on tmpfs |
| Key not in plaintext on disk | tmpfs is RAM-only; cleared on reboot |
| Key decrypted in memory only | NGINX `ssl_password_file` |
| Least-privilege access | Each server reads only its own secret path |
| Zero-downtime rotation | Vault Agent version change → `nginx -s reload` |
| Audit trail | Vault audit log records every read |
