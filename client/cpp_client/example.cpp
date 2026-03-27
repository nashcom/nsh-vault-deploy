/*
 * example.cpp — VaultClient usage example
 *
 * Simulates the CertMgr servertask flow:
 *   1. Role/secret credentials arrive from secure storage (here: env vars)
 *   2. Generate test cert material (here: hardcoded stand-ins)
 *   3. Login to Vault
 *   4. Push cert for each target server
 *   5. All sensitive strings zeroed before exit
 *
 * Build: see Makefile
 *
 * Environment variables required:
 *   VAULT_ADDR       e.g. http://127.0.0.1:8200
 *   VAULT_ROLE_ID    AppRole role_id  (from server/init/create-nginx-role.sh)
 *   VAULT_SECRET_ID  AppRole secret_id
 *
 * Optional:
 *   VAULT_MOUNT      KV v2 mount path (default: secret)
 *   VAULT_SERVER     target server FQDN (default: nginx01.example.com)
 *   VAULT_CERT_TYPE  ecdsa or rsa      (default: ecdsa)
 */

#include "vault_push.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

/* ── helpers ─────────────────────────────────────────────────────────────── */

static std::string GetEnvOrDefault(const char* pszName, const char* pszDefault)
{
    const char* pszVal = std::getenv(pszName);
    return (pszVal && *pszVal) ? pszVal : pszDefault;
}

static std::string GetEnvRequired(const char* pszName)
{
    const char* pszVal = std::getenv(pszName);
    if (!pszVal || !*pszVal)
    {
        std::cerr << "ERROR: environment variable " << pszName << " is not set\n";
        std::exit(1);
    }
    return pszVal;
}

/* ── test cert material ──────────────────────────────────────────────────────
 *
 * In the real servertask these come from:
 *   szChain   — ACME CA response (PEM chain, leaf first)
 *   szEncKey  — private key encrypted with szKeyPass immediately after generation
 *   szKeyPass — random password generated in step 1, never written to disk
 *
 * Here we use placeholder strings so the example compiles and runs without
 * openssl calls. Replace with real material for end-to-end testing against
 * a live Vault.
 */
static CertPush MakeTestCert(const std::string& szServerFQDN,
                              const std::string& szCertType)
{
    CertPush oCert;
    oCert.szServerFQDN = szServerFQDN;
    oCert.szCertType   = szCertType;

    /* Real servertask: PEM data from ACME CA response */
    oCert.szChain = "-----BEGIN CERTIFICATE-----\n"
                    "MIIBxxx...leaf cert here...\n"
                    "-----END CERTIFICATE-----\n"
                    "-----BEGIN CERTIFICATE-----\n"
                    "MIIByyy...intermediate here...\n"
                    "-----END CERTIFICATE-----\n";

    /* Real servertask: private key encrypted immediately after generation */
    oCert.szEncKey = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n"
                     "MIIFHDBOBgkqhkiG9w0BBQ0...\n"
                     "-----END ENCRYPTED PRIVATE KEY-----\n";

    /* Real servertask: random password from step 1, in memory only */
    oCert.szKeyPass  = "xK9#mPq2rT7vL4nW";

    oCert.szSerial   = "4ABB:CC12:...";
    oCert.szNotAfter = "May 12 00:00:00 2026 GMT";

    return oCert;
}


/* ── main ────────────────────────────────────────────────────────────────── */

int main()
{
    /* Credentials from environment — in production from Domino secure store */
    std::string szAddr     = GetEnvRequired("VAULT_ADDR");
    std::string szRoleId   = GetEnvRequired("VAULT_ROLE_ID");
    std::string szSecretId = GetEnvRequired("VAULT_SECRET_ID");
    std::string szMount    = GetEnvOrDefault("VAULT_MOUNT",    "secret");
    std::string szServer   = GetEnvOrDefault("VAULT_SERVER",   "nginx01.example.com");
    std::string szCertType = GetEnvOrDefault("VAULT_CERT_TYPE","ecdsa");

    std::cout << "Vault addr : " << szAddr   << "\n";
    std::cout << "Mount      : " << szMount  << "\n";
    std::cout << "Server     : " << szServer << "\n";
    std::cout << "Cert type  : " << szCertType << "\n\n";

    /* ── create client ──────────────────────────────────────────────────── */
    VaultClient oVault(szAddr, szMount);

    /* ── login ──────────────────────────────────────────────────────────── */
    /*
     * Login() zeroes szRoleId and szSecretId on return — pass by reference
     * so the originals are wiped. After this call they are empty strings.
     */
    std::cout << "Logging in with AppRole...\n";
    if (!oVault.Login(szRoleId, szSecretId))
    {
        std::cerr << "Login failed: " << oVault.LastError() << "\n";
        return 1;
    }
    std::cout << "  authenticated (HTTP " << oVault.LastHttpCode() << ")\n\n";

    /* ── push cert ──────────────────────────────────────────────────────── */
    CertPush oCert = MakeTestCert(szServer, szCertType);

    std::cout << "Pushing cert to secret/certs/"
              << oCert.szServerFQDN << "/" << oCert.szCertType << " ...\n";

    if (!oVault.PushCert(oCert))
    {
        std::cerr << "PushCert failed: " << oVault.LastError()
                  << " (HTTP " << oVault.LastHttpCode() << ")\n";
        return 1;
    }
    std::cout << "  pushed (HTTP " << oVault.LastHttpCode() << ")\n\n";

    /* ── multi-server example ───────────────────────────────────────────── */
    /*
     * Wildcard cert: push the same cert material to multiple servers.
     * Each server gets its own Vault entry under its own FQDN.
     * (In production each server would also have its own key — same cert CN
     *  but different key pairs. The push loop is identical either way.)
     */
    const std::string aszServers[] =
    {
        "nginx02.example.com",
        "nginx03.example.com",
    };

    for (const auto& szFQDN : aszServers)
    {
        CertPush oNext = MakeTestCert(szFQDN, szCertType);
        std::cout << "Pushing cert for " << szFQDN << " ...\n";

        if (!oVault.PushCert(oNext))
        {
            std::cerr << "  failed: " << oVault.LastError() << "\n";
            /* continue — push remaining servers even if one fails */
        }
        else
        {
            std::cout << "  ok\n";
        }
    }

    /*
     * VaultClient destructor zeros the token.
     * szRoleId / szSecretId were zeroed inside Login().
     */
    std::cout << "\nDone.\n";
    return 0;
}
