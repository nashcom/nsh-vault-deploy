FQDN="myserver.example.com"
CERT_FILE="vault.crt"
KEY_FILE="vault.key"

curl -s --request POST \
     -H "X-Vault-Token: $VAULT_TOKEN" \
     -H "Content-Type: application/json" \
     --data "$(jq -n \
         --rawfile chain  "$CERT_FILE" \
         --rawfile key    "$KEY_FILE" \
         --arg     cn     "$FQDN" \
         --arg     not_after "Mar 26 00:00:00 2026 GMT" \
         '{"data": {"chain": $chain, "key": $key, "cn": $cn, "not_after": $not_after}}')" \
     "$VAULT_ADDR/v1/secret/data/certs/$FQDN/tls" | jq

