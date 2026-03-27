{{- with secret "secret/data/certs/SERVER_HOSTNAME/ecdsa" -}}
{{ .Data.data.key_password }}
{{- end }}
