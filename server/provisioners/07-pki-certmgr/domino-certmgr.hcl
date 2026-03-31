# Policy: domino-certmgr
# Assigned to Domino CertMgr token for PKI certificate issuance.
# Enforces domain restrictions via the domino-certmgr role on the intermediate CA.

path "pki-intermediate/issue/domino-certmgr" {
  capabilities = ["create", "update"]
}
