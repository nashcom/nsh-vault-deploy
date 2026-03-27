# Domino server.id Password via Vault

## Use Case

HCL Domino encrypts `server.id` with a password. Today that password either
sits in `notes.ini` (`ServerKeyFilePassword=…`) or requires manual entry at
startup — neither works for automated rotation.

Goal: Vault holds the password. An Extension Manager hook fetches it when
Domino needs to open the ID file. **The password never touches disk.**

## Design

### Pull model — EM hook calls Vault directly

```
Domino startup
  → password event fires (Extension Manager hook)
  → EM callback: POST /v1/auth/approle/login  (role_id + secret_id)
  → EM callback: GET  /v1/secret/data/domino/<cn>/password
  → return password to Domino
  → memset(password_buf, 0, len)   ← zero immediately after use
```

No intermediate shared memory, no pre-start script, no tmpfs file.
The password exists in process memory only for the duration of the callback.

### Network stack

Primary: Domino's internal libcurl — compiled into `libnotes.so` (Linux) /
`nnotes.dll` (Windows). The curl symbols are exported from those libraries
and can be called directly by linking against them. No extra libraries needed
— OpenSSL is libcurl's concern, not ours.

> **Note:** The exported curl symbols are not an official or documented HCL
> API. They are an implementation detail that may change between Domino
> releases without notice.

Fallback: statically linked libcurl (brings its own OpenSSL). Used only if
the Domino-exported symbols are unavailable or incompatible. We never link
OpenSSL directly — only ever through libcurl.

### Vault Secret Structure

```
secret/data/domino/servers/<cn>/password
```

| Field       | Content                       |
|-------------|-------------------------------|
| `password`  | server.id passphrase          |
| `cn`        | Domino server CN              |
| `pushed_at` | ISO-8601 timestamp            |

The `.id` file stays on disk (it is already encrypted by Domino).
Only the password is stored in Vault.

### Vault Policy (per server)

```hcl
# policy: domino-<servername>
path "secret/data/domino/servers/DOMINO_CN/*" {
  capabilities = ["read"]
}
path "secret/metadata/domino/servers/DOMINO_CN/*" {
  capabilities = ["read"]
}
```

### Credentials on disk

```
/etc/vault-domino/role_id      — static, can be in config management
/etc/vault-domino/secret_id    — mode 0600, treated as a secret
```

Same approach as the NGINX AppRole — one role per server, scoped to its own secret path only.

## Extension Manager Implementation

### Registration (`notes.ini`)

```ini
EXTMGR_ADDINS=vaultpwd
```

Domino loads `vaultpwd.so` (Linux) / `vaultpwd.dll` (Windows) from Domino program directory at startup.

### Entry Point

```c
#include <global.h>
#include <extmgr.h>

static HEMREGISTRATION hReg;

STATUS LNPUBLIC MainEntryPoint(void)
{
    return EMRegister(
        EM_GETPASSWORD,       /* password request event          */
        EM_REG_BEFORE,        /* intercept before default handler */
        (EMHANDLER)VaultPasswordCallback,
        0,
        &hReg);
}
```

### Callback

```c
STATUS LNPUBLIC VaultPasswordCallback(EMRECORD *pRec)
{
    /* Only handle server ID password requests */
    if (pRec->EId != EM_GETPASSWORD)
        return ERR_EM_CONTINUE;

    /* Extract output parameters from the argument list */
    VARARG_PTR  ap          = pRec->Ap;
    WORD        wMaxLen     = VARARG_GET(ap, WORD);
    WORD       *pwRetLen    = VARARG_GET(ap, WORD *);
    char       *pszPassword = VARARG_GET(ap, char *);

    char szPassword[256] = {0};
    WORD wLen = 0;

    if (VaultFetchPassword(szPassword, sizeof(szPassword), &wLen) != NOERROR)
        return ERR_EM_CONTINUE;   /* let Domino fall through to default */

    wLen = min(wLen, wMaxLen);
    memmove(pszPassword, szPassword, wLen);
    *pwRetLen = wLen;

    /* Zero our local copy immediately */
    memset(szPassword, 0, sizeof(szPassword));

    return ERR_BSAFE_EXTERNAL_PASSWORD;   /* signal: password provided */
}
```

### Vault Fetch (`VaultFetchPassword`)

```c
/*
 * VaultFetchPassword — authenticate to Vault with AppRole,
 * retrieve the server.id password, return in caller-provided buffer.
 * Uses Domino's internal libcurl via libnotes.so / nnotes.dll.
 */
STATUS VaultFetchPassword(char *pszOut, WORD wMaxLen, WORD *pwLen)
{
    /* 1. Read role_id and secret_id from disk */
    char szRoleId[256]   = {0};
    char szSecretId[256] = {0};
    if (ReadCredFile("/etc/vault-domino/role_id",   szRoleId,   sizeof(szRoleId))   != NOERROR ||
        ReadCredFile("/etc/vault-domino/secret_id", szSecretId, sizeof(szSecretId)) != NOERROR)
        return ERR_MISC_INVALID_ARGS;

    /* 2. POST /v1/auth/approle/login → client token */
    char szToken[256] = {0};
    if (VaultAppRoleLogin(szRoleId, szSecretId, szToken, sizeof(szToken)) != NOERROR)
    {
        memset(szRoleId,   0, sizeof(szRoleId));
        memset(szSecretId, 0, sizeof(szSecretId));
        return ERR_MISC_INVALID_ARGS;
    }
    memset(szRoleId,   0, sizeof(szRoleId));
    memset(szSecretId, 0, sizeof(szSecretId));

    /* 3. GET /v1/secret/data/domino/servers/<cn>/password → password field */
    STATUS rc = VaultGetSecretField(szToken, "password", pszOut, wMaxLen, pwLen);

    memset(szToken, 0, sizeof(szToken));
    return rc;
}
```

Key points:
- Every intermediate buffer (`szToken`, `szRoleId`, `szSecretId`) is zeroed
  with `memset` before the function returns — success or failure
- `VaultAppRoleLogin` and `VaultGetSecretField` use Domino's internal libcurl
  via `libnotes.so` / `nnotes.dll` — reuses Domino's SSL stack without
  any additional dependencies

## Password Rotation

1. Admin or CertMgr generates a new password
2. `notes.ini` password entry (if any) is removed — no longer needed once
   the EM hook is deployed
3. New password pushed to Vault:
   ```
   vault kv put secret/domino/servers/<cn>/password \
       password="<new>" cn="<cn>" pushed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```
4. Domino server.id is re-encrypted with the new password
   (via `SECKFMChangePassword` — called by admin tooling or CertMgr)
5. On next Domino restart, the EM hook fetches the new password automatically

Steps 3 and 4 must happen atomically — push to Vault and re-encrypt the
`.id` file in the same operation, otherwise they get out of sync.

## Files (planned)

```
domino/
  helper/
    vaultpwd.c       — EM DLL: registration + callback + Vault fetch
    Makefile
  init/
    create-domino-role.sh    — Vault AppRole provisioning for a Domino server
    push-domino-password.sh  — Push/rotate password in Vault
```
