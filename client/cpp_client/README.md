# CertMgr — Vault Push from Memory

The servertask holds all certificate material in memory throughout the flow.
Nothing sensitive touches disk at any stage.

## Servertask Flow

```
1. Generate password                     (in memory)
2. Generate private key                  (in memory, encrypted with password)
3. Build CSR from key                    (in memory)
4. Submit CSR to ACME CA                 (HTTPS out)
5. Receive signed certificate chain      (in memory)
6. Validate chain + key match            (in memory)
7. VaultClient::Login()  → token         (HTTPS, role/secret zeroed after)
8. VaultClient::PushCert() for each server  (HTTPS, payload zeroed after)
9. VaultClient destructor zeroes token
```

## Dependencies

nlohmann/json is vendored in `include/nlohmann/json.hpp` — no install needed.
Only libcurl must be present on the build machine.

### Ubuntu / Debian
```bash
apt install libcurl4-openssl-dev
```

### Alpine
```bash
apk add curl-dev
```

For the planned static Alpine build add the static libraries:
```bash
apk add curl-static openssl-libs-static nghttp2-static zlib-static
```
Static link flags (to be added to Makefile when needed):
```
-lcurl -lssl -lcrypto -lnghttp2 -lz -static
```

### Red Hat / Rocky / RHEL / Fedora
```bash
dnf install libcurl-devel
```

### Windows (MinGW)
Download the curl for Windows package from https://curl.se/windows/ and
set `CURL_DIR` to the install location (see Makefile).

### Domino servertask
When built as a Domino servertask the system libcurl is replaced by
Domino's own libcurl from the Domino program directory. Dependencies
for that build path to be confirmed once the servertask is integrated.

## Build

```bash
make
make DEBUG=1   # debug build

# Windows (MinGW)
set CURL_DIR=C:\curl
make

# Run against local Vault (docker compose up -d in server/)
make run
```

## Quick Start

```bash
# Terminal 1: start Vault
cd ../../server && docker compose up -d && bash init/setup.sh

# Terminal 2: provision test server and push sample cert via the CLI scripts
bash ../../server/init/create-nginx-role.sh nginx01.example.com
bash ../../server/init/push-cert-api.sh     nginx01.example.com ecdsa

# Terminal 2: run the C++ example with the same credentials
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_ROLE_ID=$(cat ../nginx/credentials/nginx01.example.com/role_id)
export VAULT_SECRET_ID=$(cat ../nginx/credentials/nginx01.example.com/secret_id)
export VAULT_SERVER=nginx01.example.com
./vault_example
```

## API Usage

```cpp
#include "vault_push.hpp"

// Credentials from Domino secure store — never from disk files in production
VaultClient oVault("https://vault.example.com:8200", "secret");

// Login zeroes szRoleId and szSecretId on return (pass by reference)
std::string szRoleId   = GetFromSecureStore("vault_role_id");
std::string szSecretId = GetFromSecureStore("vault_secret_id");

if (!oVault.Login(szRoleId, szSecretId))
{
    // szRoleId and szSecretId are already zeroed even on failure
    LogError("Vault login: %s", oVault.LastError().c_str());
    return;
}

// Push cert — all fields come from memory (ACME response, key gen)
CertPush oCert;
oCert.szServerFQDN = "nginx01.example.com";
oCert.szCertType   = "ecdsa";
oCert.szChain      = szPemChain;     // from ACME CA response
oCert.szEncKey     = szEncryptedKey; // encrypted immediately after generation
oCert.szKeyPass    = szKeyPassword;  // random, generated in step 1
oCert.szSerial     = szSerial;
oCert.szNotAfter   = szNotAfter;

if (!oVault.PushCert(oCert))
    LogError("Vault push: %s", oVault.LastError().c_str());

// VaultClient destructor zeroes the token
```

## What Moves Over the Wire

### Step 1 — AppRole Login
```
POST /v1/auth/approle/login
{"role_id":"<id>","secret_id":"<secret>"}

← 200 {"auth":{"client_token":"hvs.xxx","lease_duration":7200,...}}
```

### Step 2 — Write Secret
```
POST /v1/secret/data/certs/nginx01.example.com/ecdsa
X-Vault-Token: hvs.xxx
{"data":{"chain":"...","encrypted_key":"...","key_password":"...",
         "cert_type":"ecdsa","serial":"...","not_after":"...","pushed_at":"..."}}

← 200 {"data":{"created_time":"...","version":3},...}
```

The `version` number in the response confirms Vault Agent on the target
server will detect the change and reload NGINX automatically.

## Files

| File | Purpose |
|------|---------|
| `vault_push.hpp` | Class definition — VaultClient, CertPush |
| `vault_push.cpp` | Implementation — Login, PushCert, HttpPost |
| `example.cpp`    | Standalone example with multi-server push |
| `Makefile`       | Linux + Windows (MinGW), debug/release |
