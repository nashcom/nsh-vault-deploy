# NGINX TLS via Vault Agent

Vault Agent authenticates to Vault with AppRole and renders certificate files
onto a tmpfs mount. NGINX uses `ssl_password_file` to decrypt the key in memory.
Nothing sensitive touches persistent disk. When CertMgr pushes a new cert to
Vault, NGINX reloads automatically within minutes — no manual steps.

## Files on tmpfs (`/run/vault/ssl/`)

| File | Mode | Content |
|------|------|---------|
| `ecdsa/server.crt` | 0644 | Full chain (leaf + intermediates) |
| `ecdsa/server.key` | 0640 root:nginx | Encrypted private key (PEM) |
| `ecdsa/ssl_password` | 0640 root:nginx | Key decryption password |
| `rsa/server.crt` | 0644 | *(if dual-stack)* |
| `rsa/server.key` | 0640 root:nginx | *(if dual-stack)* |
| `rsa/ssl_password` | 0640 root:nginx | *(if dual-stack)* |

tmpfs is RAM only — no persistent disk write, cleared on reboot.
Vault Agent repopulates on service start.

## Prerequisites

```bash
# Vault binary
curl -fsSL https://releases.hashicorp.com/vault/1.17.0/vault_1.17.0_linux_amd64.zip \
    | zcat > /usr/bin/vault && chmod 755 /usr/bin/vault

# nginx group must exist
getent group nginx || groupadd --system nginx
```

## Installation

```bash
# On the Vault host — create AppRole for this server
bash server/init/create-nginx-role.sh nginx01.example.com

# Push a test cert to validate the pipeline
bash server/init/push-sample-cert.sh nginx01.example.com ecdsa

# On the NGINX server — install agent and start service
sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200

# Dual-stack (ECDSA + RSA)
sudo bash client/nginx/install.sh nginx01.example.com https://vault.example.com:8200 both
```

## NGINX Configuration

```nginx
# Single cert (ECDSA)
ssl_certificate     /run/vault/ssl/ecdsa/server.crt;
ssl_certificate_key /run/vault/ssl/ecdsa/server.key;
ssl_password_file   /run/vault/ssl/ecdsa/ssl_password;

# Dual-stack
ssl_certificate     /run/vault/ssl/ecdsa/server.crt;
ssl_certificate_key /run/vault/ssl/ecdsa/server.key;
ssl_certificate     /run/vault/ssl/rsa/server.crt;
ssl_certificate_key /run/vault/ssl/rsa/server.key;
ssl_password_file   /run/vault/ssl/ecdsa/ssl_password;
ssl_password_file   /run/vault/ssl/rsa/ssl_password;
```

Full example generated to `/etc/vault-agent/nginx-ssl.conf.example` by install.sh.

## Operations

```bash
# Status
systemctl status vault-agent-nginx

# Follow logs (shows renders and reloads)
journalctl -fu vault-agent-nginx

# Verify files
ls -la /run/vault/ssl/ecdsa/

# Force re-render (e.g. after reinstall)
systemctl restart vault-agent-nginx

# Simulate a CertMgr cert push
bash server/init/push-sample-cert.sh nginx01.example.com ecdsa
# → Vault Agent detects new version within minutes → nginx reloads automatically
```

## Rotation Flow

```
CertMgr generates new cert+key
  → vault kv put secret/certs/<fqdn>/ecdsa chain=... encrypted_key=... key_password=...
  → Vault Agent detects new KV version (at lease renewal, default ~5 min)
  → Templates re-render to tmpfs
  → hooks/reload-nginx.sh runs: nginx -t && nginx -s reload
  → NGINX workers drain gracefully; new workers pick up new cert
  → Zero downtime
```
