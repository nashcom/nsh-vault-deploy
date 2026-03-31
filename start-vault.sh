#!/bin/bash
# start-vault.sh -- Start Vault or reset it completely
#
# Usage:
#   ./start-vault.sh           # Resume existing or start new (interactive)
#   ./start-vault.sh --scratch # Delete everything and start over

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/script_lib.sh"

MODE="${1:-interactive}"
INIT_FILE="${SCRIPT_DIR}/server/init/vault-init.json"

# Mode: Start From Scratch (full reset)

if [ "$MODE" = "--scratch" ]; then

  header "Start From Scratch - Delete Everything"
  echo "This will delete:"
  echo "  - Docker volumes (vault data)"
  echo "  - Initialization file (vault-init.json)"
  echo "  - Configuration (.env)"
  echo
  echo "You will need to run ./setup-vault.sh to reconfigure."
  echo

  read -r -p "Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
  fi

  # Use the cleanup script with force
  bash "$SCRIPT_DIR/cleanup-vault.sh" --force

  # Delete .env configuration
  ENV_FILE="${SCRIPT_DIR}/.env"
  if [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
    echo "Removed .env configuration"
  fi

  log "Vault completely reset."
  MODE="start"
fi

# Mode: Interactive (resume or start)

if [ "$MODE" = "interactive" ] && [ -f "$INIT_FILE" ]; then

  header "Vault Already Exists"
  echo "Found existing Vault initialization."
  echo
  echo "Options:"
  echo "  1. Resume (start Vault container)"
  echo "  2. Start from scratch (delete everything)"
  echo "  3. Exit"
  echo
  read -r -p "Choose (1-3): " choice
  echo

  case "$choice" in
    1)
      MODE="start"
      ;;
    2)
      MODE="--scratch"
      # Recurse to handle scratch mode
      bash "$0" --scratch
      exit 0
      ;;
    3)
      echo "Cancelled."
      exit 0
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
fi

# Start Vault Container

if [ "$MODE" = "start" ] || [ "$MODE" = "interactive" ]; then

  header "Starting Vault"

  cd "$SCRIPT_DIR"

  echo "Starting Docker container..."
  docker compose up -d

  log "Vault container started"

  # Check for vault-init.json

  if [ ! -f "$INIT_FILE" ]; then
    header "Initializing Vault"

    bash "$SCRIPT_DIR/server/init/setup.sh"

    if [ ! -f "$INIT_FILE" ]; then
      echo "ERROR: Vault initialization failed" >&2
      exit 1
    fi
  else
    echo "Vault already initialized."
  fi

  # Check for vault-init.json (contains unseal key + root token)

  if [ ! -f "$INIT_FILE" ]; then
    header "ERROR: vault-init.json Missing"
    echo "Vault is initialized but vault-init.json not found."
    echo
    echo "This file contains the unseal key and root token."
    echo
    echo "To reset everything and start over, use:"
    echo
    echo "  ./start-vault.sh --scratch"
    echo
    exit 1
  fi

  # Check for configuration

  ENV_FILE="${SCRIPT_DIR}/.env"

  if [ ! -f "$ENV_FILE" ]; then
    header "Configuration Missing"
    echo "No .env file found. Run setup-vault.sh to configure:"
    echo
    echo "  ./setup-vault.sh"
    echo
    exit 0
  fi

  log "Vault is ready to provision"

  # Display root token for UI login
  if [ -f "$INIT_FILE" ]; then
    ROOT_TOKEN=$(jq -r '.root_token' "$INIT_FILE")
    echo
    echo "========================================"
    echo "ROOT TOKEN FOR UI LOGIN"
    echo "========================================"
    echo "$ROOT_TOKEN"
    echo
  fi

  echo "Next steps:"
  echo
  echo "  ./setup-provisioners.sh      (automated deployment)"
  echo "  ./guided-tour.sh             (educational walkthrough)"
  echo
fi
