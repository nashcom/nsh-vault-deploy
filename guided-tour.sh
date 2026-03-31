#!/bin/bash
# guided-tour.sh -- Educational walkthrough of Vault provisioning
#
# This script runs all provisioners step-by-step with explanations
# and verification commands after each step.
#
# Prerequisites:
#   - .env file exists (created by setup-vault.sh)
#   - Vault is initialized and unsealed (run server/init/setup.sh)
#
# Usage:
#   bash guided-tour.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/script_lib.sh"

ENV_FILE="${SCRIPT_DIR}/.env"
INTERACTIVE=false
GUIDED=true

# Load configuration
if [ ! -f "$ENV_FILE" ]; then
  header "Configuration Missing"
  echo "No .env file found. This is needed before running the tour."
  echo
  read -r -p "Run ./setup-vault.sh now? (y/n) " -n 1
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/setup-vault.sh"
  else
    echo "Cancelled."
    exit 0
  fi
fi

LoadEnvFile "$ENV_FILE"

# Check if provisioning has already been done
SetupVaultCLI
if vault secrets list -format=json 2>/dev/null | jq -e '.["secret/"]' >/dev/null 2>&1; then
  header "ERROR: Provisioning Already Complete"
  echo "The KV secrets engine (secret/) already exists."
  echo "Running this tour again will duplicate configuration."
  echo
  echo "If you need to re-provision, use:"
  echo "  ./start-vault.sh --scratch"
  echo "  ./setup-vault.sh"
  echo "  ./guided-tour.sh"
  echo
  exit 1
fi

header "Vault Provisioning - Guided Tour"
echo
echo "We will build a complete Vault PKI infrastructure across 7 steps:"
echo
echo "  - Step 1: KV Secrets & AppRole for secret delivery"
echo "  - Step 2: Root CA - foundation of the certificate chain"
echo "  - Step 3: Intermediate CA - issues end-entity certificates"
echo "  - Step 4: ACME - automated certificate issuance"
echo "  - Step 5: Per-Server AppRole - NGINX client credentials"
echo "  - Step 6: mTLS Bootstrap - certificate-based authentication"
echo "  - Step 7: CertMgr Role - Domino integration"
echo
echo "Each step will run, then show verification commands you can try."
echo
pause_for_continue "Press any key to begin..."
clear_screen

# Step 01: KV Secrets
header "Step 1: KV Secrets & AppRole"

explain "This step enables the KV v2 secrets engine and creates an AppRole for CertMgr."
explain "AppRole is used for automated deployments - it's like a service account."

cd "$SCRIPT_DIR/server/provisioners/01-kv-secrets"
bash setup.sh

explain "✓ KV secrets engine is now available at secret/"
explain "✓ CertMgr AppRole has been created with a push policy"

show_verify \
  "vault secrets list" \
  "vault policy read certmgr-push" \
  "vault read auth/approle/role/certmgr"

pause_for_continue
clear_screen

# Step 02: Root CA
header "Step 2: PKI Root CA"

explain "This step creates the root CA certificate."
explain "The root CA is the foundation of the certificate chain."
explain "In production, the root CA is kept offline. The intermediate CA issues certs."

cd "$SCRIPT_DIR/server/provisioners/02-pki-internal-ca"
bash setup.sh

explain "✓ Root CA has been generated and saved to 02-pki-internal-ca/root-ca.crt"
explain "✓ PKI engine is ready at pki/"

show_verify \
  "vault read pki/config/urls" \
  "vault list pki/roles" \
  "vault write pki/issue/server common_name=test.${VAULT_DOMAIN} ttl=24h"

pause_for_continue
clear_screen

# Step 03: Intermediate CA
header "Step 3: PKI Intermediate CA"

explain "This step creates an Intermediate CA, signed by the Root CA."
explain "The Intermediate CA issues end-entity certificates."
explain "This architecture allows the Root CA to be protected while Intermediate can rotate."

cd "$SCRIPT_DIR/server/provisioners/03-pki-intermediate-ca"
bash setup.sh

explain "✓ Intermediate CA has been created and signed by the root"
explain "✓ PKI Intermediate engine is ready at pki-intermediate/"

show_verify \
  "vault read pki-intermediate/cert/ca_chain" \
  "vault list pki-intermediate/roles"

pause_for_continue
clear_screen

# Step 04: ACME
header "Step 4: ACME Protocol"

explain "This step enables ACME on the Intermediate CA."
explain "ACME allows clients like acme.sh and certbot to request certificates."
explain "The role:acme policy enforces domain restrictions - clients can only request ${VAULT_DOMAIN} certs."

cd "$SCRIPT_DIR/server/provisioners/04-pki-acme"
bash setup.sh

explain "✓ ACME is now enabled on pki-intermediate/"
explain "✓ ACME directory: ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory"

show_verify \
  "vault read pki-intermediate/config/acme" \
  "vault read pki-intermediate/roles/acme" \
  "curl -s ${VAULT_API_ADDR}/v1/pki-intermediate/acme/directory | jq ."

pause_for_continue
clear_screen

# Step 05: AppRole per-server
header "Step 5: Per-Server AppRole (NGINX)"

explain "This step creates an AppRole for a specific NGINX server."
explain "Each server gets its own AppRole with credentials (role_id, secret_id)."
explain "Servers use these credentials to authenticate and pull their certificates from Vault."

SERVER_HOSTNAME="${SERVER_HOSTNAME:-nginx01.example.com}"
echo "Using SERVER_HOSTNAME=$SERVER_HOSTNAME"
echo

cd "$SCRIPT_DIR/server/provisioners/05-approle-nginx"
bash setup.sh "$SERVER_HOSTNAME"

explain "✓ AppRole created for $SERVER_HOSTNAME"
explain "✓ Credentials saved to 05-approle-nginx/credentials/${SERVER_HOSTNAME}/"

show_verify \
  "vault read auth/approle/role/nginx-${SERVER_HOSTNAME}" \
  "vault policy read nginx-${SERVER_HOSTNAME}"

pause_for_continue
clear_screen

# Step 06: mTLS Bootstrap
header "Step 6: mTLS Bootstrap"

explain "This step enables Certificate-based authentication."
explain "Clients can authenticate to Vault using their own certificate."
explain "This is mutual TLS - both client and server verify each other."

cd "$SCRIPT_DIR/server/provisioners/06-mtls-bootstrap"
bash setup.sh

explain "✓ Certificate authentication is enabled"
explain "✓ Client CA certificate exported to server/tls/client-ca.crt"

show_verify \
  "vault auth list" \
  "vault read pki/roles/srvguard-client"

pause_for_continue

# Enroll a test server
explain "Now enrolling a test server for mTLS..."
cd "$SCRIPT_DIR/server/provisioners/06-mtls-bootstrap"
bash enroll.sh "${SERVER_HOSTNAME}"

explain "✓ Test server enrolled with wrap token"
explain "✓ Wrap token: 06-mtls-bootstrap/credentials/${SERVER_HOSTNAME}/wrap_token"

pause_for_continue
clear_screen

# Step 07: CertMgr PKI Role
header "Step 7: CertMgr PKI Role"

explain "This step creates a PKI role for Domino CertMgr."
explain "CertMgr will use this role to issue certificates for Domino servers."
explain "The role enforces domain restrictions (no sign-verbatim bypass)."

cd "$SCRIPT_DIR/server/provisioners/07-pki-certmgr"
bash setup.sh

explain "✓ domino-certmgr role created on pki-intermediate/"
explain "✓ Token with domino-certmgr policy generated (48h TTL)"

show_verify \
  "vault read pki-intermediate/roles/domino-certmgr" \
  "vault policy read domino-certmgr"

pause_for_continue
clear_screen

# Summary
header "Tour Complete!"

explain "Congratulations! Your Vault PKI is fully configured."
explain
explain "What you've built:"
explain "  ✓ KV secrets engine with AppRole for secret delivery"
explain "  ✓ Root CA + Intermediate CA for a production-ready PKI hierarchy"
explain "  ✓ ACME protocol for automated certificate issuance (Domino CertMgr, acme.sh, certbot)"
explain "  ✓ Per-server AppRoles for NGINX or other clients"
explain "  ✓ mTLS client authentication for mutual trust"
explain "  ✓ CertMgr role for Domino integration"
explain

display_root_token "${SCRIPT_DIR}/server/init/vault-init.json"

echo "Next steps:"
echo
echo "  - Access Vault UI: $VAULT_API_ADDR"
echo "  - Import root CA to browser: server/provisioners/02-pki-internal-ca/root-ca.crt"
echo "  - Deploy clients with credentials from server/provisioners/*/credentials/"
echo "  - Rotate tokens with: bash server/provisioners/07-pki-certmgr/renew-token.sh"
echo
