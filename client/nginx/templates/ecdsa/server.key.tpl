{{- with secret "secret/data/certs/SERVER_HOSTNAME/ecdsa" -}}
{{ .Data.data.encrypted_key }}
{{- end }}
