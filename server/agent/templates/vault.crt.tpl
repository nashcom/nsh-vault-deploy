{{- /* vault.crt.tpl — Vault's external TLS certificate chain */
     /* Secret path: secret/certs/<vault-fqdn>/tls                */
     /* Field 'chain' holds PEM leaf + intermediates               */
     /* Field 'key'   holds unencrypted PEM key (no ssl_password)  */ -}}
{{- with secret "secret/data/certs/VAULT_FQDN/tls" -}}
{{ .Data.data.chain }}
{{- end }}
