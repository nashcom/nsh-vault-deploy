/*
 * curltest.c — Domino servertask: test libcurl exports from libnotes.so
 *
 * Performs a GET request to the URL specified on the load command line
 * and logs the HTTP status and response body to the Domino console.
 *
 * Load:
 *   load curltest http://127.0.0.1:8100/v1/sys/health
 */

#include <global.h>
#include <addin.h>
#include <osfile.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ── libcurl minimal declarations ─────────────────────────────────────────── *
 * curl is exported from libnotes.so / nnotes.dll — no separate headers needed.
 * Values match curl.h; update if a future Domino ships a significantly newer
 * libcurl version.
 * ─────────────────────────────────────────────────────────────────────────── */

typedef void    CURL;
typedef int     CURLcode;

#define CURLE_OK                0
#define CURL_GLOBAL_DEFAULT     3L

#define CURLOPT_WRITEDATA       10001
#define CURLOPT_URL             10002
#define CURLOPT_SSLCERT         10025
#define CURLOPT_SSLKEY          10083
#define CURLOPT_CAINFO          10065
#define CURLOPT_HEADERDATA      10029
#define CURLOPT_TIMEOUT         13
#define CURLOPT_FOLLOWLOCATION  52
#define CURLOPT_WRITEFUNCTION   20011
#define CURLOPT_HEADERFUNCTION  20079

#define CURLINFO_RESPONSE_CODE  0x200002

extern CURLcode     curl_global_init    (long flags);
extern void         curl_global_cleanup (void);
extern CURL        *curl_easy_init      (void);
extern void         curl_easy_cleanup   (CURL *hCurl);
extern CURLcode     curl_easy_setopt    (CURL *hCurl, int nOption, ...);
extern CURLcode     curl_easy_perform   (CURL *hCurl);
extern CURLcode     curl_easy_getinfo   (CURL *hCurl, int nInfo, ...);
extern const char  *curl_easy_strerror  (CURLcode nCode);
extern const char  *curl_version        (void);

#define CURLTEST_BUFSIZE  4096

/* ── response accumulator ─────────────────────────────────────────────────── */

typedef struct {
  char   szBuf[CURLTEST_BUFSIZE];
  size_t nLen;
} RESPONSE_BUF;

static size_t HeaderCallback(void *pvData, size_t szSize, size_t szNmemb, void *pvUser)
{
  size_t nBytes = szSize * szNmemb;
  char   szLine[512] = {0};

  if (nBytes > sizeof(szLine) - 1)
    nBytes = sizeof(szLine) - 1;

  memcpy(szLine, pvData, nBytes);

  /* strip trailing CR/LF */
  while (nBytes > 0 && (szLine[nBytes-1] == '\r' || szLine[nBytes-1] == '\n'))
    szLine[--nBytes] = '\0';

  if (nBytes > 0)
    AddInLogMessageText("CurlTest: %s", NOERROR, szLine);

  return szSize * szNmemb;
}

static size_t WriteCallback(void *pvData, size_t szSize, size_t szNmemb, void *pvUser)
{
  RESPONSE_BUF *pBuf   = (RESPONSE_BUF *)pvUser;
  size_t        nBytes = szSize * szNmemb;
  size_t        nCopy  = nBytes;
  size_t        nSpace = sizeof(pBuf->szBuf) - pBuf->nLen - 1;

  if (nCopy > nSpace)
    nCopy = nSpace;

  memcpy(pBuf->szBuf + pBuf->nLen, pvData, nCopy);
  pBuf->nLen              += nCopy;
  pBuf->szBuf[pBuf->nLen]  = '\0';

  return nBytes;  /* always return full size — never signal a write error */
}

/* ── servertask entry point ───────────────────────────────────────────────── */

STATUS LNPUBLIC AddInMain(HMODULE hResourceModule, int argc, char *argv[])
{
  char         szMsg[256]     = {0};
  char         szDataDir[256] = {0};
  char         szCACert[300]  = {0};
  RESPONSE_BUF oResp          = {0};
  CURL        *hCurl           = NULL;
  CURLcode     nRC             = CURLE_OK;
  long         lHTTPCode       = 0;
  const char  *pszClientCert  = NULL;
  const char  *pszClientKey   = NULL;

  OSGetDataDirectory(szDataDir);
  snprintf(szCACert, sizeof(szCACert), "%s/cacert.pem", szDataDir);

  /* optional mTLS — set env vars to enable */
  pszClientCert = getenv("VAULT_CLIENT_CERT");
  pszClientKey  = getenv("VAULT_CLIENT_KEY");

  AddInLogMessageText("CurlTest: %s", NOERROR, curl_version());

  if (argc < 2)
  {
    AddInLogMessageText("CurlTest: usage: load curltest <url>", NOERROR);
    return NOERROR;
  }

  AddInLogMessageText("CurlTest: GET %s", NOERROR, argv[1]);

  curl_global_init(CURL_GLOBAL_DEFAULT);

  hCurl = curl_easy_init();
  if (!hCurl)
  {
    AddInLogMessageText("CurlTest: curl_easy_init failed", NOERROR);
    curl_global_cleanup();
    return NOERROR;
  }

  curl_easy_setopt(hCurl, CURLOPT_URL,            argv[1]);
  curl_easy_setopt(hCurl, CURLOPT_CAINFO,         szCACert);

  if (pszClientCert && pszClientKey)
  {
    curl_easy_setopt(hCurl, CURLOPT_SSLCERT, pszClientCert);
    curl_easy_setopt(hCurl, CURLOPT_SSLKEY,  pszClientKey);
  }

  curl_easy_setopt(hCurl, CURLOPT_HEADERFUNCTION, HeaderCallback);
  curl_easy_setopt(hCurl, CURLOPT_HEADERDATA,     NULL);
  curl_easy_setopt(hCurl, CURLOPT_WRITEFUNCTION,  WriteCallback);
  curl_easy_setopt(hCurl, CURLOPT_WRITEDATA,      &oResp);
  curl_easy_setopt(hCurl, CURLOPT_TIMEOUT,        10L);
  curl_easy_setopt(hCurl, CURLOPT_FOLLOWLOCATION, 0L);

  nRC = curl_easy_perform(hCurl);

  if (nRC != CURLE_OK)
  {
    AddInLogMessageText("CurlTest: %s", NOERROR, curl_easy_strerror(nRC));
  }
  else
  {
    curl_easy_getinfo(hCurl, CURLINFO_RESPONSE_CODE, &lHTTPCode);
    snprintf(szMsg, sizeof(szMsg), "CurlTest: HTTP %ld", lHTTPCode);
    AddInLogMessageText(szMsg, NOERROR);

    if (oResp.nLen > 0)
      AddInLogMessageText("CurlTest: %s", NOERROR, oResp.szBuf);
  }

  curl_easy_cleanup(hCurl);
  curl_global_cleanup();

  return NOERROR;
}
