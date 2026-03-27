/*
 * vault_push.cpp — Vault KV v2 push implementation
 */

#include "vault_push.hpp"

#include <cstring>
#include <ctime>
#include <sstream>
#include <iomanip>


/* ── VaultClient ctor / dtor ─────────────────────────────────────────────── */

VaultClient::VaultClient(std::string szAddr, std::string szMount)
    : m_szAddr(std::move(szAddr))
    , m_szMount(std::move(szMount))
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

VaultClient::~VaultClient()
{
    ZeroString(m_szToken);
    ZeroString(m_szLastError);
    curl_global_cleanup();
}


/* ── helpers ─────────────────────────────────────────────────────────────── */

/* Overwrite the string buffer before releasing — sensitive data only */
void VaultClient::ZeroString(std::string& s)
{
    if (!s.empty())
        memset(&s[0], 0, s.size());
    s.clear();
}

std::string VaultClient::UtcTimestamp()
{
    std::time_t t = std::time(nullptr);
    std::tm     tm = {};
#ifdef _WIN32
    gmtime_s(&tm, &t);
#else
    gmtime_r(&t, &tm);
#endif
    std::ostringstream oss;
    oss << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    return oss.str();
}

size_t VaultClient::CurlWriteCallback(void* pvData, size_t cbItem,
                                       size_t nItems, void* pvUser)
{
    auto* pszOut = static_cast<std::string*>(pvUser);
    pszOut->append(static_cast<char*>(pvData), cbItem * nItems);
    return cbItem * nItems;
}


/* ── HttpPost ────────────────────────────────────────────────────────────── */

bool VaultClient::HttpPost(const std::string&    szPath,
                            const nlohmann::json& oBody,
                            const std::string&    szToken,
                            nlohmann::json&       oResponse)
{
    std::string szUrl     = m_szAddr + szPath;
    std::string szPayload = oBody.dump();
    std::string szRawResp;

    CURL* hCurl = curl_easy_init();
    if (!hCurl)
    {
        m_szLastError = "curl_easy_init failed";
        return false;
    }

    struct curl_slist* pHeaders = nullptr;
    pHeaders = curl_slist_append(pHeaders, "Content-Type: application/json");

    if (!szToken.empty())
    {
        std::string szHdr = "X-Vault-Token: " + szToken;
        pHeaders = curl_slist_append(pHeaders, szHdr.c_str());
    }

    curl_easy_setopt(hCurl, CURLOPT_URL,           szUrl.c_str());
    curl_easy_setopt(hCurl, CURLOPT_POST,          1L);
    curl_easy_setopt(hCurl, CURLOPT_POSTFIELDS,    szPayload.c_str());
    curl_easy_setopt(hCurl, CURLOPT_HTTPHEADER,    pHeaders);
    curl_easy_setopt(hCurl, CURLOPT_WRITEFUNCTION, CurlWriteCallback);
    curl_easy_setopt(hCurl, CURLOPT_WRITEDATA,     &szRawResp);
    curl_easy_setopt(hCurl, CURLOPT_TIMEOUT,       10L);

    CURLcode rc = curl_easy_perform(hCurl);
    curl_slist_free_all(pHeaders);

    if (rc != CURLE_OK)
    {
        m_szLastError = curl_easy_strerror(rc);
        curl_easy_cleanup(hCurl);
        ZeroString(szPayload);
        return false;
    }

    long lCode = 0;
    curl_easy_getinfo(hCurl, CURLINFO_RESPONSE_CODE, &lCode);
    m_nLastHttpCode = static_cast<int>(lCode);
    curl_easy_cleanup(hCurl);

    /* Zero the serialised payload — may contain key material */
    ZeroString(szPayload);

    if (szRawResp.empty())
    {
        m_szLastError = "empty response (HTTP " + std::to_string(lCode) + ")";
        return false;
    }

    try
    {
        oResponse = nlohmann::json::parse(szRawResp);
    }
    catch (const nlohmann::json::parse_error& e)
    {
        m_szLastError = std::string("JSON parse: ") + e.what();
        return false;
    }

    return (lCode >= 200 && lCode < 300);
}


/* ── Login ───────────────────────────────────────────────────────────────── */

bool VaultClient::Login(std::string& szRoleId, std::string& szSecretId)
{
    nlohmann::json oBody =
    {
        {"role_id",   szRoleId},
        {"secret_id", szSecretId}
    };

    /* Zero credentials immediately — they live in the JSON body only */
    ZeroString(szRoleId);
    ZeroString(szSecretId);

    nlohmann::json oResp;
    if (!HttpPost("/v1/auth/approle/login", oBody, {}, oResp))
    {
        if (m_szLastError.empty())
            m_szLastError = "login failed (HTTP " + std::to_string(m_nLastHttpCode) + ")";
        return false;
    }

    try
    {
        m_szToken = oResp.at("auth").at("client_token").get<std::string>();
    }
    catch (const nlohmann::json::exception& e)
    {
        m_szLastError = std::string("token parse: ") + e.what();
        return false;
    }

    return true;
}


/* ── PushCert ────────────────────────────────────────────────────────────── */

bool VaultClient::PushCert(const CertPush& oCert)
{
    if (m_szToken.empty())
    {
        m_szLastError = "not authenticated — call Login() first";
        return false;
    }

    /* Path: /v1/<mount>/data/certs/<fqdn>/<type> */
    std::string szPath = "/v1/" + m_szMount + "/data/certs/"
                       + oCert.szServerFQDN + "/" + oCert.szCertType;

    nlohmann::json oBody =
    {
        {"data",
         {
             {"chain",         oCert.szChain},
             {"encrypted_key", oCert.szEncKey},
             {"key_password",  oCert.szKeyPass},
             {"cert_type",     oCert.szCertType},
             {"serial",        oCert.szSerial},
             {"not_after",     oCert.szNotAfter},
             {"pushed_at",     UtcTimestamp()}
         }}
    };

    nlohmann::json oResp;
    if (!HttpPost(szPath, oBody, m_szToken, oResp))
    {
        if (m_szLastError.empty())
            m_szLastError = "push failed (HTTP " + std::to_string(m_nLastHttpCode) + ")";
        return false;
    }

    return true;
}
