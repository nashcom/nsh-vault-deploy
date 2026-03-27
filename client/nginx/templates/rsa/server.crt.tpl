{{- with secret "secret/data/certs/SERVER_HOSTNAME/rsa" -}}
{{ .Data.data.chain }}
{{- end }}
