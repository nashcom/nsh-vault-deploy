// vault-fetcher — fetches TLS cert/key/password from Vault KV v2 and
// writes them to a directory (typically a tmpfs mount shared with NGINX).
// Runs on the host; the target container never touches Vault.
//
// Environment variables:
//   VAULT_ADDR          — Vault server URL (e.g. https://vault.example.com:8200)
//   VAULT_ROLE_ID       — AppRole role_id
//   VAULT_SECRET_ID     — AppRole secret_id (prefer file via VAULT_SECRET_ID_FILE)
//   VAULT_SECRET_ID_FILE— path to file containing secret_id (takes precedence)
//   VAULT_CACERT        — path to CA certificate for Vault TLS verification
//   CERT_FQDN           — server FQDN (used as secret path)
//   CERT_TYPE           — rsa or ecdsa (default: rsa)
//   CERT_OUT_DIR        — output directory (default: /run/certs)
//   NGINX_CONTAINER     — container name to send SIGHUP (default: nginx)
//   RENEW_BEFORE_DAYS   — days before expiry to renew (default: 30)

package main

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// ── config ────────────────────────────────────────────────────────────────────

type Config struct {
	VaultAddr      string
	RoleID         string
	SecretID       string
	CACertPath     string
	FQDN           string
	CertType       string
	OutDir         string
	NginxContainer string
	RenewBefore    time.Duration
}

func loadConfig() (Config, error) {
	c := Config{
		VaultAddr:      mustEnv("VAULT_ADDR"),
		RoleID:         mustEnv("VAULT_ROLE_ID"),
		CACertPath:     mustEnv("VAULT_CACERT"),
		FQDN:           mustEnv("CERT_FQDN"),
		CertType:       envOr("CERT_TYPE", "rsa"),
		OutDir:         envOr("CERT_OUT_DIR", "/run/certs"),
		NginxContainer: envOr("NGINX_CONTAINER", "nginx"),
	}

	// secret_id — file takes precedence over env var
	if f := os.Getenv("VAULT_SECRET_ID_FILE"); f != "" {
		b, err := os.ReadFile(f)
		if err != nil {
			return c, fmt.Errorf("reading VAULT_SECRET_ID_FILE: %w", err)
		}
		c.SecretID = strings.TrimSpace(string(b))
	} else {
		c.SecretID = mustEnv("VAULT_SECRET_ID")
	}

	days, err := strconv.Atoi(envOr("RENEW_BEFORE_DAYS", "30"))
	if err != nil {
		return c, fmt.Errorf("RENEW_BEFORE_DAYS must be an integer: %w", err)
	}
	c.RenewBefore = time.Duration(days) * 24 * time.Hour

	return c, nil
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		fmt.Fprintf(os.Stderr, "vault-fetcher: %s is required\n", key)
		os.Exit(1)
	}
	return v
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// ── HTTP client ───────────────────────────────────────────────────────────────

func newHTTPClient(caCertPath string) (*http.Client, error) {
	pem, err := os.ReadFile(caCertPath)
	if err != nil {
		return nil, fmt.Errorf("reading CA cert %s: %w", caCertPath, err)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pem) {
		return nil, fmt.Errorf("no valid certificates found in %s", caCertPath)
	}

	return &http.Client{
		Timeout: 15 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				RootCAs:    pool,
				MinVersion: tls.VersionTLS12,
			},
		},
	}, nil
}

// ── Vault API ─────────────────────────────────────────────────────────────────

func appRoleLogin(client *http.Client, addr, roleID, secretID string) (string, error) {
	body, _ := json.Marshal(map[string]string{
		"role_id":   roleID,
		"secret_id": secretID,
	})

	resp, err := client.Post(addr+"/v1/auth/approle/login", "application/json", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("AppRole login request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("AppRole login: HTTP %d", resp.StatusCode)
	}

	var result struct {
		Auth struct {
			ClientToken string `json:"client_token"`
		} `json:"auth"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("AppRole login decode: %w", err)
	}
	if result.Auth.ClientToken == "" {
		return "", fmt.Errorf("AppRole login: empty token in response")
	}

	return result.Auth.ClientToken, nil
}

func fetchSecret(client *http.Client, addr, token, fqdn, certType string) (map[string]string, error) {
	path := fmt.Sprintf("%s/v1/secret/data/certs/%s/%s", addr, fqdn, certType)

	req, _ := http.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("X-Vault-Token", token)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("secret fetch request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("secret fetch: HTTP %d", resp.StatusCode)
	}

	var result struct {
		Data struct {
			Data map[string]string `json:"data"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("secret fetch decode: %w", err)
	}

	return result.Data.Data, nil
}

// ── file output ───────────────────────────────────────────────────────────────

func writeFiles(outDir string, secret map[string]string) error {
	files := map[string]string{
		"server.crt":   secret["chain"],
		"server.key":   secret["encrypted_key"],
		"ssl.password": secret["key_password"],
	}

	for name, content := range files {
		if content == "" {
			return fmt.Errorf("secret field missing for %s", name)
		}
		path := outDir + "/" + name
		if err := os.WriteFile(path, []byte(content), 0640); err != nil {
			return fmt.Errorf("writing %s: %w", path, err)
		}
	}

	return nil
}

// ── renewal scheduling ────────────────────────────────────────────────────────

func nextRenewal(secret map[string]string, renewBefore time.Duration) (time.Duration, error) {
	notAfterStr, ok := secret["not_after"]
	if !ok || notAfterStr == "" {
		// no expiry field — check again in 24h
		return 24 * time.Hour, nil
	}

	notAfter, err := time.Parse("Jan 2 15:04:05 2006 MST", notAfterStr)
	if err != nil {
		return 0, fmt.Errorf("parsing not_after %q: %w", notAfterStr, err)
	}

	renewAt := notAfter.Add(-renewBefore)
	wait := time.Until(renewAt)

	if wait < 0 {
		// already past renewal window — fetch immediately next cycle
		return 0, nil
	}

	return wait, nil
}

// ── NGINX reload ──────────────────────────────────────────────────────────────

func reloadNginx(container string) error {
	out, err := exec.Command("docker", "kill", "--signal=HUP", container).CombinedOutput()
	if err != nil {
		return fmt.Errorf("docker kill --signal=HUP %s: %w: %s", container, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// ── main loop ─────────────────────────────────────────────────────────────────

func main() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "vault-fetcher: config error: %v\n", err)
		os.Exit(1)
	}

	if err := os.MkdirAll(cfg.OutDir, 0750); err != nil {
		fmt.Fprintf(os.Stderr, "vault-fetcher: mkdir %s: %v\n", cfg.OutDir, err)
		os.Exit(1)
	}

	httpClient, err := newHTTPClient(cfg.CACertPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "vault-fetcher: %v\n", err)
		os.Exit(1)
	}

	io.Discard.Write(nil) // suppress unused import warning

	for {
		fmt.Printf("[%s] authenticating to Vault\n", time.Now().Format(time.RFC3339))

		token, err := appRoleLogin(httpClient, cfg.VaultAddr, cfg.RoleID, cfg.SecretID)
		if err != nil {
			fmt.Fprintf(os.Stderr, "vault-fetcher: login failed: %v — retrying in 60s\n", err)
			time.Sleep(60 * time.Second)
			continue
		}

		secret, err := fetchSecret(httpClient, cfg.VaultAddr, token, cfg.FQDN, cfg.CertType)
		if err != nil {
			fmt.Fprintf(os.Stderr, "vault-fetcher: fetch failed: %v — retrying in 60s\n", err)
			time.Sleep(60 * time.Second)
			continue
		}

		if err := writeFiles(cfg.OutDir, secret); err != nil {
			fmt.Fprintf(os.Stderr, "vault-fetcher: write failed: %v — retrying in 60s\n", err)
			time.Sleep(60 * time.Second)
			continue
		}

		fmt.Printf("[%s] cert written to %s\n", time.Now().Format(time.RFC3339), cfg.OutDir)

		if err := reloadNginx(cfg.NginxContainer); err != nil {
			fmt.Fprintf(os.Stderr, "vault-fetcher: reload failed: %v\n", err)
		} else {
			fmt.Printf("[%s] NGINX reloaded\n", time.Now().Format(time.RFC3339))
		}

		wait, err := nextRenewal(secret, cfg.RenewBefore)
		if err != nil {
			fmt.Fprintf(os.Stderr, "vault-fetcher: renewal schedule: %v — checking again in 24h\n", err)
			wait = 24 * time.Hour
		}

		if wait == 0 {
			fmt.Printf("[%s] already in renewal window — renewing immediately\n", time.Now().Format(time.RFC3339))
			continue
		}

		fmt.Printf("[%s] next renewal check in %s\n", time.Now().Format(time.RFC3339), wait.Round(time.Minute))
		time.Sleep(wait)
	}
}
