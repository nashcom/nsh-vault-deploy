{{- /* vault.key.tpl — Vault's external TLS private key (unencrypted)  */
     /* Vault reads the key directly — no ssl_password_file mechanism.  */
     /* Protected by Vault access controls, written to tmpfs if possible */ -}}
{{- with secret "secret/data/certs/VAULT_FQDN/tls" -}}
{{ .Data.data.key }}
{{- end }}
