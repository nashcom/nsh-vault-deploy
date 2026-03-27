{{- with secret "secret/data/certs/SERVER_HOSTNAME/rsa" -}}
{{ .Data.data.encrypted_key }}
{{- end }}
