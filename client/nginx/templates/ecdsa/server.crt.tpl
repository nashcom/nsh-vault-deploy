{{- with secret "secret/data/certs/SERVER_HOSTNAME/ecdsa" -}}
{{ .Data.data.chain }}
{{- end }}
