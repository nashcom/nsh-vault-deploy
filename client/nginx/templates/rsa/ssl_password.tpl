{{- with secret "secret/data/certs/SERVER_HOSTNAME/rsa" -}}
{{ .Data.data.key_password }}
{{- end }}
