#pragma once

/*
 * vault_push.hpp — Vault KV v2 push client for CertMgr
 *
 * Pushes certificate material to HashiCorp Vault entirely from memory.
 * No intermediate files are written at any stage.
 *
 * Dependencies:
 *   libcurl          — HTTPS transport (via libnotes.so / nnotes.dll when
 *                      built as a Domino addin, or system libcurl otherwise)
 *   nlohmann/json    — JSON serialisation (header-only)
 */

#include <string>
#include <nlohmann/json.hpp>
#include <curl/curl.h>


/* ── CertPush ────────────────────────────────────────────────────────────────
 *
 * All fields are copied into VaultClient::PushCert() — caller may free
 * or zero the originals immediately after the call returns.
 */
struct CertPush
{
    std::string szServerFQDN;   /* target server,  e.g. nginx01.example.com  */
    std::string szCertType;     /* "ecdsa" or "rsa"                           */
    std::string szChain;        /* full PEM chain (leaf + intermediates)      */
    std::string szEncKey;       /* AES-256 encrypted PEM private key          */
    std::string szKeyPass;      /* key decryption password                    */
    std::string szSerial;       /* certificate serial number                  */
    std::string szNotAfter;     /* expiry timestamp (openssl enddate format)  */
};


/* ── VaultClient ─────────────────────────────────────────────────────────────
 *
 * One client instance per Vault address / KV mount.
 * Not thread-safe — create one instance per thread or serialise access.
 *
 * Typical call sequence:
 *
 *   VaultClient vc("https://vault.example.com:8200", "secret");
 *   vc.Login(szRoleId, szSecretId);   // role/secret zeroed after token acquired
 *   vc.PushCert(cert);
 *   // destructor zeros token
 */
class VaultClient
{
public:
    VaultClient(std::string szAddr, std::string szMount);
    ~VaultClient();

    /* Disable copy — contains sensitive material */
    VaultClient(const VaultClient&)            = delete;
    VaultClient& operator=(const VaultClient&) = delete;

    /*
     * Login — POST /v1/auth/approle/login
     * Acquires a client token. Zeroes szRoleId and szSecretId on return
     * regardless of success or failure.
     * Returns true on success; LastError() has details on failure.
     */
    bool Login(std::string& szRoleId, std::string& szSecretId);

    /*
     * PushCert — POST /v1/<mount>/data/certs/<fqdn>/<type>
     * Builds the JSON payload in memory and pushes it.
     * Calls Login() automatically if not yet authenticated.
     * Returns true on success; LastError() has details on failure.
     */
    bool PushCert(const CertPush& oCert);

    const std::string& LastError() const { return m_szLastError; }
    int                LastHttpCode() const { return m_nLastHttpCode; }

private:
    std::string m_szAddr;
    std::string m_szMount;
    std::string m_szToken;
    std::string m_szLastError;
    int         m_nLastHttpCode = 0;

    bool        HttpPost(const std::string& szPath,
                         const nlohmann::json& oBody,
                         const std::string& szToken,
                         nlohmann::json& oResponse);

    static void ZeroString(std::string& s);
    static std::string UtcTimestamp();
    static size_t CurlWriteCallback(void* pvData, size_t cbItem,
                                    size_t nItems, void* pvUser);
};
